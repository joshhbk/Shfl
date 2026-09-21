import SwiftUI
import UIKit

@Observable
@MainActor
final class AppPlaybackSessionCoordinator {
    let player: ShufflePlayer

    @ObservationIgnored private let authorizer: MusicAuthorizing
    @ObservationIgnored private let playbackTransport: PlaybackTransport
    @ObservationIgnored private let archive: SessionArchive
    @ObservationIgnored private let recorder: SessionRecorder
    @ObservationIgnored private let scrobbleTracker: ScrobbleTracker
    @ObservationIgnored private let lifecyclePersistenceHook: (() -> Void)?

    var isAuthorized = false
    var isLoading = true
    var loadingMessage = "Loading..."
    var authorizationError: String?

    private(set) var didRestorePlaybackState = false

    @ObservationIgnored private var backgroundObserver: NSObjectProtocol?

    init(
        player: ShufflePlayer,
        authorizer: MusicAuthorizing,
        playbackTransport: PlaybackTransport,
        archive: SessionArchive,
        scrobbleTracker: ScrobbleTracker,
        lifecyclePersistenceHook: (() -> Void)? = nil
    ) {
        self.player = player
        self.authorizer = authorizer
        self.playbackTransport = playbackTransport
        self.archive = archive
        self.scrobbleTracker = scrobbleTracker
        self.lifecyclePersistenceHook = lifecyclePersistenceHook
        self.recorder = SessionRecorder(archive: archive, player: player)

        // Each consumer owns its own subscription to the shared seam.
        scrobbleTracker.start(consuming: player.playbackTransitions)
        recorder.start()
        subscribeToBackgroundNotification()
    }

    deinit {
        if let observer = backgroundObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func onAppear() async {
        print("📱 onAppear: Loading songs and playback state...")

        async let authStatus = authorizer.isAuthorized
        async let loadedSession = try? archive.loadAsync()

        let archived = await loadedSession ?? .empty
        isAuthorized = await authStatus

        print("📱 onAppear: Loaded \(archived.pool.count) songs, playbackState=\(archived.session != nil ? "exists" : "nil")")

        if !archived.pool.isEmpty {
            try? player.seedSongs(archived.pool)
        }

        if let record = archived.session {
            print("📱 onAppear: Attempting to restore session (song=\(record.currentSongID), position=\(record.playbackPosition))")
            let restored = await restore(record)
            if !restored {
                print("📱 onAppear: Saved session could not be restored; next play will create a fresh shuffle")
            }
        } else {
            print("📱 onAppear: No saved listening session")
        }

        isLoading = false
    }

    func requestAuthorization() async {
        isAuthorized = await authorizer.requestAuthorization()
        if !isAuthorized {
            authorizationError = "Apple Music access is required to use Shuffled. Please enable it in Settings."
        }
    }

    func handleDidEnterBackground() {
        print("📱 App entering background - checkpointing session...")
        recorder.checkpoint(position: playbackTransport.currentPlaybackTime)
        lifecyclePersistenceHook?()
    }

    /// The editable song pool changed; persist it without rewriting the session.
    func poolDidChange() {
        recorder.poolDidChange()
    }

    private func subscribeToBackgroundNotification() {
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleDidEnterBackground()
            }
        }
    }

    private func restore(_ record: ListeningSessionRecord) async -> Bool {
        switch record.restored() {
        case .restore(let session, let currentSongID, _, let position):
            let success = await player.restore(
                session,
                currentSongID: currentSongID,
                playbackPosition: position
            )
            if success {
                didRestorePlaybackState = true
            }
            return success

        case .discard(let reason):
            print("📱 onAppear: Discarding saved session (\(reason))")
            if reason == .stale {
                try? archive.clearActiveSession()
            }
            return false
        }
    }
}