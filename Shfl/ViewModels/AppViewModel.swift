import SwiftData
import SwiftUI
import UIKit

@Observable
@MainActor
final class AppViewModel {
    let player: ShufflePlayer
    @ObservationIgnored let musicService: MusicService
    @ObservationIgnored private let repository: SongRepository
    @ObservationIgnored private let playbackStateRepository: PlaybackStateRepository
    @ObservationIgnored private let scrobbleTracker: ScrobbleTracker
    @ObservationIgnored private let appSettings: AppSettings

    var isAuthorized = false
    var isLoading = true
    var loadingMessage = "Loading..."
    var showingManage = false
    var showingPicker = false
    var showingPickerDirect = false
    var showingSettings = false
    var authorizationError: String?

    /// Whether playback state was restored from persistence
    private(set) var didRestorePlaybackState = false

    init(musicService: MusicService, modelContext: ModelContext, appSettings: AppSettings) {
        self.musicService = musicService
        self.player = ShufflePlayer(musicService: musicService)
        self.repository = SongRepository(modelContext: modelContext)
        self.playbackStateRepository = PlaybackStateRepository(modelContext: modelContext)
        self.appSettings = appSettings

        // Setup scrobbling
        let lastFMTransport = LastFMTransport(
            apiKey: LastFMConfig.apiKey,
            sharedSecret: LastFMConfig.sharedSecret
        )
        let scrobbleManager = ScrobbleManager(transports: [lastFMTransport])
        self.scrobbleTracker = ScrobbleTracker(scrobbleManager: scrobbleManager, musicService: musicService)

        // Start observing playback state for scrobbling
        startObservingPlaybackState()

        // Subscribe to background notification for saving state
        subscribeToBackgroundNotification()
    }

    @ObservationIgnored private var scrobbleObservationTask: Task<Void, Never>?
    @ObservationIgnored private var backgroundObserver: NSObjectProtocol?
    @ObservationIgnored private var lastPersistedSongId: String?

    deinit {
        scrobbleObservationTask?.cancel()
        if let observer = backgroundObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func subscribeToBackgroundNotification() {
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Dispatch to MainActor synchronously since we're on main queue
            MainActor.assumeIsolated {
                guard let self else { return }
                print("📱 App entering background - persisting state...")
                self.persistSongs()
                self.persistPlaybackState()
                print("📱 State persisted")
            }
        }
    }

    private func startObservingPlaybackState() {
        // Use Swift Observation to watch player.playbackState changes
        // This is event-driven, no polling required
        scrobbleObservationTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }

                // Capture current state and notify scrobbler
                let state = self.player.playbackState
                self.scrobbleTracker.onPlaybackStateChanged(state)

                // Persist when the current song changes (covers skip, natural advance, etc.)
                let currentSongId = state.currentSongId
                if currentSongId != self.lastPersistedSongId, state.isActive {
                    self.persistPlaybackState()
                    self.lastPersistedSongId = currentSongId
                }

                // Wait until playbackState changes using Observation
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


    func onAppear() async {
        // Check authorization and load songs + playback state in parallel
        loadingMessage = "Loading your music..."
        print("📱 onAppear: Loading songs and playback state...")

        async let authStatus = musicService.isAuthorized
        async let loadedSongs = try? repository.loadSongsAsync()
        async let loadedPlaybackState = try? playbackStateRepository.loadPlaybackStateAsync()

        // Wait for all to complete
        let songs = await loadedSongs ?? []
        let playbackState = await loadedPlaybackState
        isAuthorized = await authStatus

        print("📱 onAppear: Loaded \(songs.count) songs, playbackState=\(playbackState != nil ? "exists" : "nil")")

        // Batch-add songs (O(n) instead of O(n²))
        if !songs.isEmpty {
            try? player.addSongs(songs)
        }

        // Try to restore playback state if available
        if !player.songs.isEmpty {
            loadingMessage = "Preparing playback..."

            if let state = playbackState {
                print("📱 onAppear: Attempting to restore playback state (song=\(state.currentSongId ?? "nil"), position=\(state.playbackPosition))")
                let restored = await restorePlaybackState(state)
                if !restored {
                    // Restoration failed - prepare fresh queue
                    try? await player.prepareQueue(algorithm: appSettings.shuffleAlgorithm)
                }
            } else {
                // No saved state - prepare fresh queue
                print("📱 onAppear: No saved playback state, preparing fresh queue")
                try? await player.prepareQueue(algorithm: appSettings.shuffleAlgorithm)
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

    func persistSongs() {
        do {
            try repository.saveSongs(player.allSongs)
        } catch {
            print("Failed to save songs: \(error)")
        }
    }

    func openManage() {
        showingManage = true
    }

    func closeManage() {
        showingManage = false
        persistSongs()
    }

    func openPicker() {
        showingPicker = true
    }

    func closePicker() {
        showingPicker = false
        persistSongs()
    }

    func openPickerDirect() {
        showingPickerDirect = true
    }

    func closePickerDirect() {
        showingPickerDirect = false
        persistSongs()
    }

    func openSettings() {
        showingSettings = true
    }

    func closeSettings() {
        showingSettings = false
    }

    // MARK: - Playback State Persistence

    /// Persists the current playback state to SwiftData
    func persistPlaybackState() {
        // Only persist if we have a valid state to save
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
        // Use player's resolved song ID (library ID) - not MusicKit's catalog ID
        let currentSongId = currentState.currentSongId
        let currentSongTitle = currentState.currentSong?.title ?? "nil"
        let playbackTime = musicService.currentPlaybackTime

        print("💾 Persisting state:")
        print("💾   currentState: \(currentState)")
        print("💾   currentSongId: \(currentSongId ?? "nil")")
        print("💾   currentSongTitle: \(currentSongTitle)")
        print("💾   playbackTime: \(playbackTime)")
        print("💾   queueOrder: \(queueOrder.count) songs, first=\(queueOrder.first ?? "nil")")
        print("💾   playedIds: \(playedIds.count)")

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
            print("💾 Saved playback state: song=\(state.currentSongId ?? "nil"), position=\(state.playbackPosition), queueOrder=\(queueOrder.count)")
        } catch {
            print("💾 Failed to save playback state: \(error)")
        }
    }

    /// Restores playback state from persistence
    /// - Returns: True if restoration was successful
    private func restorePlaybackState(_ state: PersistedPlaybackState) async -> Bool {
        // Check if state is stale
        if playbackStateRepository.isStateStale(state) {
            print("🔄 Playback state is stale (>7 days), using fresh shuffle")
            try? playbackStateRepository.clearPlaybackState()
            return false
        }

        let queueOrder = state.queueOrder
        let playedIds = state.playedSongIds

        // Validate we have a non-empty queue
        guard !queueOrder.isEmpty else {
            print("🔄 Saved queue is empty, using fresh shuffle")
            return false
        }

        // Attempt restoration
        let success = await player.restoreQueue(
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
