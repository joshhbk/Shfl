import SwiftData
import SwiftUI

@Observable
@MainActor
final class AppViewModel {
    let player: ShufflePlayer
    @ObservationIgnored let musicService: MusicService
    @ObservationIgnored private let repository: SongRepository
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

    init(musicService: MusicService, modelContext: ModelContext, appSettings: AppSettings) {
        self.musicService = musicService
        self.player = ShufflePlayer(musicService: musicService)
        self.repository = SongRepository(modelContext: modelContext)
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
    }

    @ObservationIgnored private var scrobbleObservationTask: Task<Void, Never>?

    deinit {
        scrobbleObservationTask?.cancel()
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
        // Check authorization and load songs in parallel (both can run concurrently)
        loadingMessage = "Loading your music..."
        async let authStatus = musicService.isAuthorized
        async let loadedSongs = try? repository.loadSongsAsync()

        // Wait for both to complete
        let songs = await loadedSongs ?? []
        isAuthorized = await authStatus

        // Batch-add songs (O(n) instead of O(n²))
        if !songs.isEmpty {
            try? player.addSongs(songs)
        }

        // Prepare queue before dismissing loading screen
        if !player.songs.isEmpty {
            loadingMessage = "Preparing playback..."
            try? await player.prepareQueue(algorithm: appSettings.shuffleAlgorithm)
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
}
