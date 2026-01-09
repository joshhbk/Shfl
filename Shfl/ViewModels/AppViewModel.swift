import Combine
import SwiftData
import SwiftUI

@MainActor
final class AppViewModel: ObservableObject {
    let player: ShufflePlayer
    let musicService: MusicService
    private let repository: SongRepository
    private let scrobbleTracker: ScrobbleTracker
    private var cancellables = Set<AnyCancellable>()

    @Published var isAuthorized = false
    @Published var isLoading = true
    @Published var loadingMessage = "Loading..."
    @Published var showingManage = false
    @Published var showingPicker = false
    @Published var showingPickerDirect = false
    @Published var showingSettings = false
    @Published var authorizationError: String?

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

        // Forward playback state to scrobble tracker
        player.$playbackState
            .sink { [weak self] state in
                self?.scrobbleTracker.onPlaybackStateChanged(state)
            }
            .store(in: &cancellables)
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
