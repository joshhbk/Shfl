import SwiftUI
import UIKit

@Observable
@MainActor
final class AppPlaybackSessionCoordinator {
    let player: ShufflePlayer

    @ObservationIgnored private let authorizer: MusicAuthorizing
    @ObservationIgnored private let playbackTransport: PlaybackTransport
    @ObservationIgnored private let sessionSnapshotService: SessionSnapshotService
    @ObservationIgnored private let scrobbleTracker: ScrobbleTracker
    @ObservationIgnored private let lifecyclePersistenceHook: (() -> Void)?

    var isAuthorized = false
    var isLoading = true
    var loadingMessage = "Loading..."
    var authorizationError: String?

    private(set) var didRestorePlaybackState = false

    @ObservationIgnored private var playbackTransitionTask: Task<Void, Never>?
    @ObservationIgnored private var backgroundObserver: NSObjectProtocol?

    init(
        player: ShufflePlayer,
        authorizer: MusicAuthorizing,
        playbackTransport: PlaybackTransport,
        sessionSnapshotService: SessionSnapshotService,
        scrobbleTracker: ScrobbleTracker,
        lifecyclePersistenceHook: (() -> Void)? = nil
    ) {
        self.player = player
        self.authorizer = authorizer
        self.playbackTransport = playbackTransport
        self.sessionSnapshotService = sessionSnapshotService
        self.scrobbleTracker = scrobbleTracker
        self.lifecyclePersistenceHook = lifecyclePersistenceHook

        startObservingPlaybackTransitions()
        subscribeToBackgroundNotification()
    }

    deinit {
        playbackTransitionTask?.cancel()
        if let observer = backgroundObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func onAppear() async {
        print("📱 onAppear: Loading songs and playback state...")

        async let authStatus = authorizer.isAuthorized
        async let loadedSession = try? sessionSnapshotService.load()

        let sessionSnapshot = await loadedSession ?? .empty
        let songs = sessionSnapshot.songs
        let playbackState = sessionSnapshot.playback
        isAuthorized = await authStatus

        print("📱 onAppear: Loaded \(songs.count) songs, playbackState=\(playbackState != nil ? "exists" : "nil")")

        if !songs.isEmpty {
            try? player.seedSongs(songs)
        }

        if !player.allSongs.isEmpty {
            if let state = playbackState {
                print("📱 onAppear: Attempting to restore playback state (song=\(state.currentSongId ?? "nil"), position=\(state.playbackPosition))")
                let restored = await restorePlaybackState(state)
                if !restored {
                    print("📱 onAppear: Saved session could not be restored; next play will create a fresh shuffle")
                }
            }
        } else {
            print("📱 onAppear: No songs loaded")
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
        print("📱 App entering background - persisting state...")
        persistCurrentSession()
        lifecyclePersistenceHook?()
        print("📱 State persisted")
    }

    func persistSongs() {
        persistCurrentSession()
    }

    func persistPlaybackState() {
        persistCurrentSession()
    }

    private func persistCurrentSession() {
        do {
            try sessionSnapshotService.saveCurrentSession(
                from: player,
                playbackTime: playbackTransport.currentPlaybackTime
            )
        } catch {
            print("💾 Failed to save session snapshot: \(error)")
        }
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

    private func startObservingPlaybackTransitions() {
        let transitions = player.playbackTransitions
        playbackTransitionTask = Task { @MainActor [weak self] in
            for await transition in transitions {
                guard !Task.isCancelled, let self else { return }
                self.scrobbleTracker.onPlaybackTransition(transition)
                do {
                    try self.sessionSnapshotService.savePlaybackTransition(
                        transition,
                        songs: self.player.allSongs
                    )
                } catch {
                    print("💾 Failed to save session snapshot: \(error)")
                }
            }
        }
    }

    private func restorePlaybackState(_ state: PlaybackSessionSnapshot) async -> Bool {
        let success = await sessionSnapshotService.restorePlaybackState(
            state,
            player: player
        )
        if success {
            didRestorePlaybackState = true
        }
        return success
    }
}
