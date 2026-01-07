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

    /// Debug: The last shuffled queue order (for verifying shuffle algorithms)
    @Published private(set) var lastShuffledQueue: [Song] = []
    /// Debug: The algorithm used for the last shuffle
    @Published private(set) var lastUsedAlgorithm: ShuffleAlgorithm = .noRepeat

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

    private var algorithmObserver: NSObjectProtocol?

    init(musicService: MusicService) {
        self.musicService = musicService
        observePlaybackState()
        observeAlgorithmChanges()
    }

    private func observeAlgorithmChanges() {
        algorithmObserver = NotificationCenter.default.addObserver(
            forName: .shuffleAlgorithmChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.reshuffleWithNewAlgorithm()
            }
        }
    }

    private func reshuffleWithNewAlgorithm() async {
        guard !songs.isEmpty, playbackState.isActive else { return }

        let algorithmRaw = UserDefaults.standard.string(forKey: "shuffleAlgorithm") ?? ShuffleAlgorithm.noRepeat.rawValue
        let algorithm = ShuffleAlgorithm(rawValue: algorithmRaw) ?? .noRepeat

        print("🎲 Algorithm changed to \(algorithm.displayName), reshuffling...")

        // Get currently playing song
        let currentSongId = playbackState.currentSongId

        // Filter out played songs AND the currently playing song
        let upcomingSongs = songs.filter { song in
            !playedSongIds.contains(song.id) && song.id != currentSongId
        }

        let shuffler = QueueShuffler(algorithm: algorithm)
        let shuffledUpcoming = shuffler.shuffle(upcomingSongs)

        // Build full queue: current song first (if exists), then shuffled upcoming
        var newQueue: [Song] = []
        if let currentId = currentSongId, let currentSong = songs.first(where: { $0.id == currentId }) {
            newQueue.append(currentSong)
        }
        newQueue.append(contentsOf: shuffledUpcoming)

        lastShuffledQueue = newQueue
        lastUsedAlgorithm = algorithm

        print("🎲 New queue order: \(newQueue.map { "\($0.title) by \($0.artist)" })")

        do {
            try await musicService.setQueue(songs: newQueue)
            // Need to call play() to make the new queue take effect mid-playback
            try await musicService.play()
            print("🎲 setQueue and play() succeeded")
        } catch {
            print("🎲 setQueue/play FAILED: \(error)")
        }
    }

    deinit {
        stateTask?.cancel()
        if let observer = algorithmObserver {
            NotificationCenter.default.removeObserver(observer)
        }
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

        // Upstream: Shuffle Logic
        let algorithmRaw = UserDefaults.standard.string(forKey: "shuffleAlgorithm") ?? ShuffleAlgorithm.noRepeat.rawValue
        let algorithm = ShuffleAlgorithm(rawValue: algorithmRaw) ?? .noRepeat
        let shuffler = QueueShuffler(algorithm: algorithm)
        let shuffledSongs = shuffler.shuffle(songs)
        lastShuffledQueue = shuffledSongs
        
        lastUsedAlgorithm = algorithm
        print("🎲 Prepared queue with algorithm: \(algorithm.displayName)")

        // Revert: Simple blocking setQueue (but using shuffledSongs)
        try await musicService.setQueue(songs: shuffledSongs)
        preparedSongIds = Set(songs.map(\.id))
    }

    // MARK: - Playback Control

    func play() async throws {
        guard !songs.isEmpty else { return }
        playedSongIds.removeAll()
        lastObservedSongId = nil

        if !isQueuePrepared {
            try await prepareQueue()
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
