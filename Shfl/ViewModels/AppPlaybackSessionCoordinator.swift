import SwiftUI
import UIKit

@Observable
@MainActor
final class AppPlaybackSessionCoordinator {
    let player: ShufflePlayer
    let playbackCoordinator: PlaybackCoordinator

    @ObservationIgnored private let musicService: MusicService
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
        musicService: MusicService,
        sessionSnapshotService: SessionSnapshotService,
        scrobbleTracker: ScrobbleTracker,
        lifecyclePersistenceHook: (() -> Void)? = nil
    ) {
        self.player = player
        self.playbackCoordinator = playbackCoordinator
        self.musicService = musicService
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

        async let authStatus = musicService.isAuthorized
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
        isAuthorized = await musicService.requestAuthorization()
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
        let sessionSnapshot = AppSessionSnapshot(
            songs: player.allSongs,
            playback: currentPlaybackSnapshot()
        )

        let playbackSnapshot = sessionSnapshot.playback
        if !player.hasRestorableState {
            print("💾 No restorable playback state to save; persisting songs and clearing playback snapshot")
        }

        let currentSongId = playbackSnapshot?.currentSongId
        let currentSongTitle = player.playbackState.currentSong?.title ?? "nil"
        let playbackTime = musicService.currentPlaybackTime
        let queueOrder = playbackSnapshot?.queueOrder ?? []
        let playedIds = playbackSnapshot?.playedSongIds ?? []

        #if DEBUG
        print("💾 Persisting state:")
        print("💾   currentSongId: \(currentSongId ?? "nil")")
        print("💾   currentSongTitle: \(currentSongTitle)")
        print("💾   playbackTime: \(playbackTime)")
        print("💾   queueOrder: \(queueOrder.count) songs, first=\(queueOrder.first ?? "nil")")
        print("💾   playedIds: \(playedIds.count)")
        #endif

        do {
            try sessionSnapshotService.save(sessionSnapshot)
            lastPersistedSongId = playbackSnapshot?.currentSongId
            #if DEBUG
            if let playbackSnapshot {
                print("💾 Saved playback state: song=\(playbackSnapshot.currentSongId ?? "nil"), position=\(playbackSnapshot.playbackPosition), queueOrder=\(queueOrder.count)")
            } else {
                print("💾 Cleared playback state while saving song snapshot")
            }
            #endif
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

    private func currentPlaybackSnapshot() -> PlaybackSessionSnapshot? {
        guard player.hasRestorableState else { return nil }

        let currentState = player.playbackState
        return PlaybackSessionSnapshot(
            currentSongId: currentState.currentSongId,
            playbackPosition: musicService.currentPlaybackTime,
            savedAt: Date(),
            queueOrder: player.currentQueueOrder,
            playedSongIds: player.currentPlayedSongIds
        )
    }

    private func restorePlaybackState(_ state: PlaybackSessionSnapshot) async -> Bool {
        if sessionSnapshotService.isPlaybackStateStale(state) {
            print("🔄 Playback state is stale (>7 days), using fresh shuffle")
            try? sessionSnapshotService.clearPlayback()
            return false
        }

        let queueOrder = state.queueOrder
        let playedIds = state.playedSongIds

        guard !queueOrder.isEmpty else {
            print("🔄 Saved queue is empty, using fresh shuffle")
            return false
        }

        let success = await playbackCoordinator.restoreSession(
            queueOrder: queueOrder,
            currentSongId: state.currentSongId,
            playedIds: playedIds,
            playbackPosition: state.playbackPosition
        )

        if success {
            didRestorePlaybackState = true
            print("🔄 Restored playback state: song=\(state.currentSongId ?? "nil"), position=\(state.playbackPosition)")
        } else {
            print("🔄 Failed to restore queue, using fresh shuffle")
        }

        return success
    }
}
