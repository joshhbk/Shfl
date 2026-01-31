import SwiftData
import SwiftUI

@Observable
@MainActor
final class AppViewModel {
    let player: ShufflePlayer
    @ObservationIgnored let musicService: MusicService
    @ObservationIgnored private let repository: SongRepository
    @ObservationIgnored private let scrobbleTracker: ScrobbleTracker

    var isAuthorized = false
    var isLoading = true
    var loadingMessage = "Loading..."
    var showingManage = false
    var showingPicker = false
    var showingPickerDirect = false
    var showingSettings = false
    var authorizationError: String?

    init(musicService: MusicService, modelContext: ModelContext) {
        self.musicService = musicService
        self.player = ShufflePlayer(musicService: musicService)
        self.repository = SongRepository(modelContext: modelContext)

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
        // Track last state to avoid duplicate notifications
        var lastState: PlaybackState?

        scrobbleObservationTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }

                // Check if state changed
                let currentState = self.player.playbackState
                if currentState != lastState {
                    lastState = currentState
                    self.scrobbleTracker.onPlaybackStateChanged(currentState)
                }

                // Poll at reasonable interval - scrobbling doesn't need instant updates
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }


    func onAppear() async {
        // Check authorization in parallel with song loading
        loadingMessage = "Loading your music..."
        async let authStatus = musicService.isAuthorized

        // Load songs (synchronous SwiftData call, runs on MainActor)
        var songs: [Song] = []
        do {
            songs = try repository.loadSongs()
        } catch {
            print("Failed to load songs: \(error)")
        }

        // Batch-add songs (O(n) instead of O(n²))
        if !songs.isEmpty {
            try? player.addSongs(songs)
        }

        // Wait for auth check
        isAuthorized = await authStatus

        // Prepare queue before dismissing loading screen
        if !player.songs.isEmpty {
            loadingMessage = "Preparing playback..."
            try? await player.prepareQueue()
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
