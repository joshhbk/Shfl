import SwiftUI
import UIKit

@Observable
@MainActor
final class AppPlaybackSessionCoordinator {
    let player: ShufflePlayer
    let playbackCoordinator: PlaybackCoordinator

    @ObservationIgnored private let musicService: MusicService
    @ObservationIgnored private let repository: SongRepository
    @ObservationIgnored private let playbackStateRepository: PlaybackStateRepository
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
        repository: SongRepository,
        playbackStateRepository: PlaybackStateRepository,
        scrobbleTracker: ScrobbleTracker,
        lifecyclePersistenceHook: (() -> Void)? = nil
    ) {
        self.player = player
        self.playbackCoordinator = playbackCoordinator
        self.musicService = musicService
        self.repository = repository
        self.playbackStateRepository = playbackStateRepository
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
        loadingMessage = "Loading your music..."
        print("📱 onAppear: Loading songs and playback state...")

        async let authStatus = musicService.isAuthorized
        async let loadedSongs = try? repository.loadSongsAsync()
        async let loadedPlaybackState = try? playbackStateRepository.loadPlaybackStateAsync()

        let songs = await loadedSongs ?? []
        let playbackState = await loadedPlaybackState
        isAuthorized = await authStatus

        print("📱 onAppear: Loaded \(songs.count) songs, playbackState=\(playbackState != nil ? "exists" : "nil")")

        if !songs.isEmpty {
            try? await playbackCoordinator.seedSongs(songs)
        }

        if !player.songs.isEmpty {
            loadingMessage = "Preparing playback..."

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
        persistSongs()
        persistPlaybackState()
        lifecyclePersistenceHook?()
        print("📱 State persisted")
    }

    func persistSongs() {
        do {
            try repository.saveSongs(player.allSongs)
        } catch {
            print("Failed to save songs: \(error)")
        }
    }

    func persistPlaybackState() {
        guard player.hasRestorableState else {
            print("💾 No restorable state to save")
            return
        }

        let currentState = player.playbackState
        let isPlaying: Bool
        switch currentState {
        case .playing:
            isPlaying = true
        default:
            isPlaying = false
        }

        let queueOrder = player.currentQueueOrder
        let playedIds = player.currentPlayedSongIds
        let currentSongId = currentState.currentSongId
        let currentSongTitle = currentState.currentSong?.title ?? "nil"
        let playbackTime = musicService.currentPlaybackTime

        #if DEBUG
        print("💾 Persisting state:")
        print("💾   currentSongId: \(currentSongId ?? "nil")")
        print("💾   currentSongTitle: \(currentSongTitle)")
        print("💾   playbackTime: \(playbackTime)")
        print("💾   queueOrder: \(queueOrder.count) songs, first=\(queueOrder.first ?? "nil")")
        print("💾   playedIds: \(playedIds.count)")
        #endif

        let state = PersistedPlaybackState(
            currentSongId: currentSongId,
            playbackPosition: playbackTime,
            wasPlaying: isPlaying,
            queueOrder: queueOrder,
            playedSongIds: playedIds
        )

        do {
            try playbackStateRepository.savePlaybackState(state)
            lastPersistedSongId = state.currentSongId
            #if DEBUG
            print("💾 Saved playback state: song=\(state.currentSongId ?? "nil"), position=\(state.playbackPosition), queueOrder=\(queueOrder.count)")
            #endif
        } catch {
            print("💾 Failed to save playback state: \(error)")
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

    private func restorePlaybackState(_ state: PersistedPlaybackSnapshot) async -> Bool {
        if playbackStateRepository.isStateStale(state) {
            print("🔄 Playback state is stale (>7 days), using fresh shuffle")
            try? playbackStateRepository.clearPlaybackState()
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
