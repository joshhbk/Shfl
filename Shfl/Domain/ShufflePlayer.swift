import Combine
import Foundation

enum ShufflePlayerError: Error, Equatable {
    case capacityReached
    case notAuthorized
    case playbackFailed(String)
}

@MainActor
final class ShufflePlayer: ObservableObject {
    static let maxSongs = 120

    private let musicService: MusicService
    @Published private(set) var songs: [Song] = []
    private var stateTask: Task<Void, Never>?

    @Published private(set) var playbackState: PlaybackState = .empty

    var songCount: Int { songs.count }
    var allSongs: [Song] { songs }
    var capacity: Int { Self.maxSongs }
    var remainingCapacity: Int { Self.maxSongs - songs.count }

    init(musicService: MusicService) {
        self.musicService = musicService
        observePlaybackState()
    }

    deinit {
        stateTask?.cancel()
    }

    private func observePlaybackState() {
        stateTask = Task { [weak self] in
            guard let self else { return }
            for await state in musicService.playbackStateStream {
                self.playbackState = state
            }
        }
    }

    // MARK: - Song Management

    func addSong(_ song: Song) throws {
        guard songs.count < Self.maxSongs else {
            throw ShufflePlayerError.capacityReached
        }
        guard !songs.contains(where: { $0.id == song.id }) else {
            return // Already added
        }
        songs.append(song)
    }

    func removeSong(id: String) {
        songs.removeAll { $0.id == id }
    }

    func removeAllSongs() {
        songs.removeAll()
    }

    func containsSong(id: String) -> Bool {
        songs.contains { $0.id == id }
    }

    // MARK: - Playback Control

    func play() async throws {
        guard !songs.isEmpty else { return }
        try await musicService.setQueue(songs: songs)
        try await musicService.play()
    }

    func pause() async {
        await musicService.pause()
    }

    func skipToNext() async throws {
        try await musicService.skipToNext()
    }

    func skipToPrevious() async throws {
        try await musicService.skipToPrevious()
    }

    func restartOrSkipToPrevious() async throws {
        try await musicService.restartOrSkipToPrevious()
    }

    func togglePlayback() async throws {
        switch playbackState {
        case .empty, .stopped:
            try await play()
        case .playing:
            await pause()
        case .paused:
            try await musicService.play()
        case .loading:
            // Do nothing while loading
            break
        case .error:
            // Try to play again
            try await play()
        }
    }
}
