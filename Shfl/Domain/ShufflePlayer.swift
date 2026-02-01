import Foundation

enum ShufflePlayerError: Error, Equatable {
    case capacityReached
    case notAuthorized
    case playbackFailed(String)
}

@Observable
@MainActor
final class ShufflePlayer {
    static let maxSongs = 120

    @ObservationIgnored private let musicService: MusicService
    private(set) var songs: [Song] = []
    @ObservationIgnored private var songIds: Set<String> = []
    @ObservationIgnored private var stateTask: Task<Void, Never>?

    private(set) var playbackState: PlaybackState = .empty

    /// Debug: The last shuffled queue order (for verifying shuffle algorithms)
    private(set) var lastShuffledQueue: [Song] = []
    /// Debug: The algorithm used for the last shuffle
    private(set) var lastUsedAlgorithm: ShuffleAlgorithm = .noRepeat

    @ObservationIgnored private var playedSongIds: Set<String> = []
    @ObservationIgnored private var lastObservedSongId: String?
    @ObservationIgnored private var queueValid = false

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

    /// Called when shuffle algorithm changes. Views should call this via onChange(of: appSettings.shuffleAlgorithm).
    func reshuffleWithNewAlgorithm(_ algorithm: ShuffleAlgorithm) async {
        guard !songs.isEmpty, playbackState.isActive else { return }

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
    }

    private func observePlaybackState() {
        stateTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await state in self.musicService.playbackStateStream {
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
        guard !songIds.contains(song.id) else {
            return // Already added
        }
        songs.append(song)
        songIds.insert(song.id)
        queueValid = false
        rebuildQueueIfPlaying()
    }

    func addSongs(_ newSongs: [Song]) throws {
        let uniqueNewSongs = newSongs.filter { !songIds.contains($0.id) }

        let availableCapacity = Self.maxSongs - songs.count
        guard uniqueNewSongs.count <= availableCapacity else {
            throw ShufflePlayerError.capacityReached
        }

        songs.append(contentsOf: uniqueNewSongs)
        songIds.formUnion(uniqueNewSongs.map(\.id))
        queueValid = false
        // Don't rebuild queue during initial load - not playing yet
    }

    func removeSong(id: String) {
        songs.removeAll { $0.id == id }
        songIds.remove(id)
        queueValid = false
        rebuildQueueIfPlaying()
    }

    func removeAllSongs() {
        songs.removeAll()
        songIds.removeAll()
        playedSongIds.removeAll()
        lastObservedSongId = nil
        queueValid = false
    }

    func containsSong(id: String) -> Bool {
        songIds.contains(id)
    }

    // MARK: - Queue Preparation

    func prepareQueue(algorithm: ShuffleAlgorithm? = nil) async throws {
        guard !songs.isEmpty else { return }

        // Use provided algorithm or fall back to UserDefaults
        let effectiveAlgorithm: ShuffleAlgorithm
        if let algorithm {
            effectiveAlgorithm = algorithm
        } else {
            let algorithmRaw = UserDefaults.standard.string(forKey: "shuffleAlgorithm") ?? ShuffleAlgorithm.noRepeat.rawValue
            effectiveAlgorithm = ShuffleAlgorithm(rawValue: algorithmRaw) ?? .noRepeat
        }

        let shuffler = QueueShuffler(algorithm: effectiveAlgorithm)
        let shuffledSongs = shuffler.shuffle(songs)
        lastShuffledQueue = shuffledSongs
        lastUsedAlgorithm = effectiveAlgorithm
        print("🎲 Prepared queue with algorithm: \(effectiveAlgorithm.displayName)")

        try await musicService.setQueue(songs: shuffledSongs)
        queueValid = true
    }

    // MARK: - Playback Control

    func play() async throws {
        guard !songs.isEmpty else { return }
        playedSongIds.removeAll()
        lastObservedSongId = nil

        if !queueValid {
            // Emit loading state for immediate UI feedback
            if let firstSong = songs.first {
                playbackState = .loading(firstSong)
            }
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
