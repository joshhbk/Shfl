import Combine
import SwiftData
import SwiftUI

@MainActor
final class AppViewModel: ObservableObject {
    let player: ShufflePlayer
    let musicService: MusicService
    private let repository: SongRepository
    private var scrobbleTracker: ScrobbleTracker?
    private var cancellables = Set<AnyCancellable>()

    @Published var isAuthorized = false
    @Published var isLoading = true
    @Published var showingManage = false
    @Published var showingPicker = false
    @Published var showingPickerDirect = false
    @Published var showingSettings = false
    @Published var authorizationError: String?

    init(musicService: MusicService, modelContext: ModelContext) {
        self.musicService = musicService
        self.player = ShufflePlayer(musicService: musicService)
        self.repository = SongRepository(modelContext: modelContext)
        // Scrobbling setup deferred to after initial load for faster startup
    }

    func onAppear() async {
        isAuthorized = await musicService.isAuthorized

        do {
            let songs = try repository.loadSongs()
            for song in songs {
                try? player.addSong(song)
            }
        } catch {
            print("Failed to load songs: \(error)")
        }

        // Mark loading complete - UI is now interactive
        isLoading = false

        // Deferred initialization: setup non-critical services after UI is ready
        setupScrobbling()

        // Prepare queue in background for instant playback
        Task { try? await player.prepareQueue() }
    }

    private func setupScrobbling() {
        let lastFMTransport = LastFMTransport(
            apiKey: LastFMConfig.apiKey,
            sharedSecret: LastFMConfig.sharedSecret
        )
        let scrobbleManager = ScrobbleManager(transports: [lastFMTransport])
        self.scrobbleTracker = ScrobbleTracker(scrobbleManager: scrobbleManager, musicService: musicService)

        // Forward playback state to scrobble tracker
        player.$playbackState
            .sink { [weak self] state in
                self?.scrobbleTracker?.onPlaybackStateChanged(state)
            }
            .store(in: &cancellables)
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
