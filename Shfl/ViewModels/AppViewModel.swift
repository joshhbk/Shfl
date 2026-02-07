import SwiftData
import SwiftUI
import UIKit

@Observable
@MainActor
final class AppViewModel {
    let player: ShufflePlayer
    let playbackCoordinator: PlaybackCoordinator
    @ObservationIgnored let musicService: MusicService
    @ObservationIgnored let lastFMTransport: LastFMTransport
    @ObservationIgnored private let repository: SongRepository
    @ObservationIgnored private let playbackStateRepository: PlaybackStateRepository
    @ObservationIgnored private let scrobbleTracker: ScrobbleTracker
    @ObservationIgnored private let appSettings: AppSettings

    var isAuthorized = false
    var isShuffling = false
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
        let player = ShufflePlayer(musicService: musicService)
        self.player = player
        self.playbackCoordinator = PlaybackCoordinator(player: player, appSettings: appSettings)
        self.repository = SongRepository(modelContext: modelContext)
        self.playbackStateRepository = PlaybackStateRepository(modelContext: modelContext)
        self.appSettings = appSettings

        // Setup scrobbling
        self.lastFMTransport = LastFMTransport(
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
        // Use Swift Observation to watch player.playbackState changes.
        // MusicKit emits objectWillChange many times per second during playback,
        // so we filter to only act on meaningful transitions (song change, play/pause).
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

                    // Persist on song changes only when actively playing to avoid clobbering
                    // restored paused-position state during startup hydration.
                    if songChanged, state.isPlaying, currentSongId != self.lastPersistedSongId {
                        self.persistPlaybackState()
                        self.lastPersistedSongId = currentSongId
                    }

                    previousSongId = currentSongId
                    previousIsPlaying = state.isPlaying
                    previousIsActive = state.isActive
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
            try? await playbackCoordinator.seedSongs(songs)
        }

        // Try to restore playback state if available
        if !player.songs.isEmpty {
            loadingMessage = "Preparing playback..."

            if let state = playbackState {
                print("📱 onAppear: Attempting to restore playback state (song=\(state.currentSongId ?? "nil"), position=\(state.playbackPosition))")
                let restored = await restorePlaybackState(state)
                if !restored {
                    // Restoration failed - prepare fresh queue
                    try? await playbackCoordinator.prepareQueue()
                }
            } else {
                // No saved state - prepare fresh queue
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

    func persistSongs() {
        do {
            try repository.saveSongs(player.allSongs)
        } catch {
            print("Failed to save songs: \(error)")
        }
    }

    func shuffleAll() async {
        isShuffling = true
        do {
            let algorithmRaw = UserDefaults.standard.string(forKey: "autofillAlgorithm") ?? "random"
            let algorithm = AutofillAlgorithm(rawValue: algorithmRaw) ?? .random
            let source = LibraryAutofillSource(musicService: musicService, algorithm: algorithm)
            let songs = try await source.fetchSongs(excluding: Set(), limit: ShufflePlayer.maxSongs)
            try await playbackCoordinator.seedSongs(songs)
            try await playbackCoordinator.play()
            persistSongs()
        } catch {
            print("Failed to shuffle all: \(error)")
        }
        // Clear after play() returns — view guards isShuffling in both
        // the empty and loading slots to keep the spinner visible until .playing
        isShuffling = false
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

    // MARK: - Coordinator Commands

    func onShuffleAlgorithmChanged(_ algorithm: ShuffleAlgorithm) async {
        await playbackCoordinator.reshuffleAlgorithm(algorithm)
    }

    func togglePlayback() async {
        try? await playbackCoordinator.togglePlayback()
    }

    func skipToNext() async {
        try? await playbackCoordinator.skipToNext()
    }

    func restartOrSkipToPrevious() async {
        try? await playbackCoordinator.restartOrSkipToPrevious()
    }

    func addSong(_ song: Song) async throws {
        try await playbackCoordinator.addSong(song)
    }

    func addSongsWithQueueRebuild(_ songs: [Song]) async throws {
        try await playbackCoordinator.addSongsWithQueueRebuild(songs)
    }

    func removeSong(id: String) async {
        await playbackCoordinator.removeSong(id: id)
    }

    func removeAllSongs() async {
        await playbackCoordinator.removeAllSongs()
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
