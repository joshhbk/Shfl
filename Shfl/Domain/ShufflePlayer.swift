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

    private var playedSongIds: Set<String> = []
    private var lastObservedSongId: String?
    private var preparedSongIds: Set<String> = []

    private var isQueuePrepared: Bool {
        Set(songs.map(\.id)) == preparedSongIds
    }

    var songCount: Int { songs.count }
    var allSongs: [Song] { songs }
    var capacity: Int { Self.maxSongs }
    var remainingCapacity: Int { Self.maxSongs - songs.count }

    /// Exposed for testing only
    var playedSongIdsForTesting: Set<String> { playedSongIds }

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
                self.handlePlaybackStateChange(state)
            }
        }
    }

    private func handlePlaybackStateChange(_ newState: PlaybackState) {
        let newSongId = newState.currentSongId

        // Song changed - add previous to history
        if let lastId = lastObservedSongId, lastId != newSongId {
            playedSongIds.insert(lastId)
        }
        lastObservedSongId = newSongId

        // Clear history on stop/empty/error
        switch newState {
        case .stopped, .empty, .error:
            playedSongIds.removeAll()
            lastObservedSongId = nil
        default:
            break
        }

        playbackState = newState
    }

    private func rebuildQueueIfPlaying() {
        guard playbackState.isActive else { return }

        let upcomingSongs = songs.filter { !playedSongIds.contains($0.id) }
        guard !upcomingSongs.isEmpty else { return }

        Task {
            try? await musicService.setQueue(songs: upcomingSongs)
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
        rebuildQueueIfPlaying()
    }

    func removeSong(id: String) {
        songs.removeAll { $0.id == id }
        rebuildQueueIfPlaying()
    }

    func removeAllSongs() {
        songs.removeAll()
        playedSongIds.removeAll()
        lastObservedSongId = nil
    }

    func containsSong(id: String) -> Bool {
        songs.contains { $0.id == id }
    }

    // MARK: - Queue Preparation

    func prepareQueue() async throws {
        guard !songs.isEmpty else { return }
        try await musicService.setQueue(songs: songs)
        preparedSongIds = Set(songs.map(\.id))
    }

    // MARK: - Playback Control

    func play() async throws {
        guard !songs.isEmpty else { return }
        playedSongIds.removeAll()
        lastObservedSongId = nil

        if !isQueuePrepared {
            try await musicService.setQueue(songs: songs)
            preparedSongIds = Set(songs.map(\.id))
        }
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
