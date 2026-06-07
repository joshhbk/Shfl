import SwiftUI
import UIKit

@Observable
@MainActor
final class AppPlaybackSessionCoordinator {
    let player: ShufflePlayer
    let playbackCoordinator: PlaybackCoordinator

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

    @ObservationIgnored private var scrobbleObservationTask: Task<Void, Never>?
    @ObservationIgnored private var backgroundObserver: NSObjectProtocol?
    @ObservationIgnored private var lastPersistedSongId: String?

    init(
        player: ShufflePlayer,
        playbackCoordinator: PlaybackCoordinator,
        authorizer: MusicAuthorizing,
        playbackTransport: PlaybackTransport,
        sessionSnapshotService: SessionSnapshotService,
        scrobbleTracker: ScrobbleTracker,
        lifecyclePersistenceHook: (() -> Void)? = nil
    ) {
        self.player = player
        self.playbackCoordinator = playbackCoordinator
        self.authorizer = authorizer
        self.playbackTransport = playbackTransport
        self.sessionSnapshotService = sessionSnapshotService
        self.scrobbleTracker = scrobbleTracker
        self.lifecyclePersistenceHook = lifecyclePersistenceHook

        startObservingPlaybackState()
        subscribeToBackgroundNotification()
    }

    deinit {
        scrobbleObservationTask?.cancel()
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
            try? await playbackCoordinator.seedSongs(songs)
        }

        if !player.allSongs.isEmpty {
            if let state = playbackState {
                print("📱 onAppear: Attempting to restore playback state (song=\(state.currentSongId ?? "nil"), position=\(state.playbackPosition))")
                let restored = await restorePlaybackState(state)
                if !restored {
                    try? await playbackCoordinator.prepareQueue()
                }
            } else {
                print("📱 onAppear: No saved playback state, preparing fresh queue")
                try? await playbackCoordinator.prepareQueue()
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
            lastPersistedSongId = player.playbackState.currentSongId
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

    private func startObservingPlaybackState() {
        scrobbleObservationTask = Task { @MainActor [weak self] in
            var previousSongId: String?
            var previousIsPlaying = false
            var previousIsActive = false

            while !Task.isCancelled {
                guard let self else { return }

                let state = self.player.playbackState
                let currentSongId = state.currentSongId
                let songChanged = currentSongId != previousSongId
                let playStateChanged = state.isPlaying != previousIsPlaying
                let activeStatusChanged = state.isActive != previousIsActive

                if songChanged || playStateChanged || activeStatusChanged {
                    self.scrobbleTracker.onPlaybackStateChanged(state)

                    if songChanged, state.isPlaying, currentSongId != self.lastPersistedSongId {
                        self.persistPlaybackState()
                        self.lastPersistedSongId = currentSongId
                    }

                    previousSongId = currentSongId
                    previousIsPlaying = state.isPlaying
                    previousIsActive = state.isActive
                }

                await withCheckedContinuation { continuation in
                    withObservationTracking {
                        _ = self.player.playbackState
                    } onChange: {
                        continuation.resume()
                    }
                }
            }
        }
    }


    private func restorePlaybackState(_ state: PlaybackSessionSnapshot) async -> Bool {
        let success = await sessionSnapshotService.restorePlaybackState(
            state,
            playbackCoordinator: playbackCoordinator
        )
        if success {
            didRestorePlaybackState = true
        }
        return success
    }
}
