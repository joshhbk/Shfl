import Combine
import SwiftData
import SwiftUI

@MainActor
final class AppViewModel: ObservableObject {
    let player: ShufflePlayer
    let musicService: MusicService
    private let repository: SongRepository

    @Published var isAuthorized = false
    @Published var showingManage = false
    @Published var showingPicker = false
    @Published var showingPickerDirect = false
    @Published var authorizationError: String?

    init(musicService: MusicService, modelContext: ModelContext) {
        self.musicService = musicService
        self.player = ShufflePlayer(musicService: musicService)
        self.repository = SongRepository(modelContext: modelContext)
    }

    func onAppear() async {
        isAuthorized = await musicService.isAuthorized

        // Prefetch library in background for faster access later
        Task {
            await musicService.prefetchLibrary()
        }

        do {
            let songs = try repository.loadSongs()
            for song in songs {
                try? player.addSong(song)
            }
        } catch {
            print("Failed to load songs: \(error)")
        }
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
}
