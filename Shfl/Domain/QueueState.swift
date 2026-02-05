import Foundation

/// Immutable queue state - single source of truth for queue management.
/// All mutations return a new state instance, making state transitions explicit and testable.
struct QueueState: Equatable, Sendable {
    /// The pool of songs available for shuffling.
    let songPool: [Song]

    /// The current queue order (shuffled from songPool).
    let queueOrder: [Song]

    /// IDs of songs that have been played in the current session.
    let playedIds: Set<String>

    /// Index of the currently playing song in queueOrder.
    let currentIndex: Int

    /// The shuffle algorithm used for this queue.
    let algorithm: ShuffleAlgorithm

    /// Fast lookup set for song pool IDs.
    private let poolIds: Set<String>

    // MARK: - Initialization

    init(
        songPool: [Song] = [],
        queueOrder: [Song] = [],
        playedIds: Set<String> = [],
        currentIndex: Int = 0,
        algorithm: ShuffleAlgorithm = .noRepeat
    ) {
        self.songPool = songPool
        self.queueOrder = queueOrder
        self.playedIds = playedIds
        self.currentIndex = currentIndex
        self.algorithm = algorithm
        self.poolIds = Set(songPool.map(\.id))
    }

    /// Empty initial state.
    static let empty = QueueState()

    // MARK: - Computed Properties

    /// The currently playing song, if any.
    var currentSong: Song? {
        guard currentIndex >= 0 && currentIndex < queueOrder.count else { return nil }
        return queueOrder[currentIndex]
    }

    /// ID of the current song.
    var currentSongId: String? { currentSong?.id }

    /// Songs remaining in the queue (including current).
    var upcomingSongs: [Song] {
        guard currentIndex < queueOrder.count else { return [] }
        return Array(queueOrder[currentIndex...])
    }

    /// Number of songs in the pool.
    var songCount: Int { songPool.count }

    /// Maximum capacity for songs.
    static let maxSongs = 120

    /// Remaining capacity for adding songs.
    var remainingCapacity: Int { Self.maxSongs - songPool.count }

    /// Whether the queue has songs.
    var isEmpty: Bool { songPool.isEmpty }

    /// Whether there's a valid queue ready to play.
    var hasQueue: Bool { !queueOrder.isEmpty }

    /// Whether there are more songs after the current one.
    var hasNext: Bool { currentIndex < queueOrder.count - 1 }

    /// Whether there are songs before the current one.
    var hasPrevious: Bool { currentIndex > 0 }

    /// Whether the queue is out of sync with the song pool.
    /// True when songs have been added to or removed from the pool since the queue was built.
    var isQueueStale: Bool {
        guard hasQueue else { return false }
        let queueIds = Set(queueOrder.map(\.id))
        return queueIds != poolIds
    }

    /// Invalidate the queue while preserving the song pool.
    /// Used when the algorithm changes while not playing.
    func invalidatingQueue() -> QueueState {
        QueueState(
            songPool: songPool,
            queueOrder: [],
            playedIds: [],
            currentIndex: 0,
            algorithm: algorithm
        )
    }

    // MARK: - Query Methods

    /// Check if a song is in the pool.
    func containsSong(id: String) -> Bool {
        poolIds.contains(id)
    }

    /// Check if a song has been played.
    func hasPlayed(id: String) -> Bool {
        playedIds.contains(id)
    }

    // MARK: - Song Pool Mutations

    /// Add a song to the pool.
    /// Returns nil if at capacity or song already exists.
    func addingSong(_ song: Song) -> QueueState? {
        guard songPool.count < Self.maxSongs else { return nil }
        guard !poolIds.contains(song.id) else { return self }

        return QueueState(
            songPool: songPool + [song],
            queueOrder: queueOrder,
            playedIds: playedIds,
            currentIndex: currentIndex,
            algorithm: algorithm
        )
    }

    /// Add multiple songs to the pool.
    /// Returns nil if exceeds capacity.
    func addingSongs(_ songs: [Song]) -> QueueState? {
        let uniqueNewSongs = songs.filter { !poolIds.contains($0.id) }
        guard songPool.count + uniqueNewSongs.count <= Self.maxSongs else { return nil }

        return QueueState(
            songPool: songPool + uniqueNewSongs,
            queueOrder: queueOrder,
            playedIds: playedIds,
            currentIndex: currentIndex,
            algorithm: algorithm
        )
    }

    /// Remove a song from the pool.
    func removingSong(id: String) -> QueueState {
        let newPool = songPool.filter { $0.id != id }
        let newQueue = queueOrder.filter { $0.id != id }
        let newPlayedIds = playedIds.filter { $0 != id }

        // Adjust current index if needed
        let removedBeforeCurrent = queueOrder.prefix(currentIndex).contains { $0.id == id }
        let newIndex = removedBeforeCurrent ? max(0, currentIndex - 1) : currentIndex

        return QueueState(
            songPool: newPool,
            queueOrder: newQueue,
            playedIds: newPlayedIds,
            currentIndex: min(newIndex, max(0, newQueue.count - 1)),
            algorithm: algorithm
        )
    }

    /// Remove all songs and reset state.
    func cleared() -> QueueState {
        .empty
    }

    /// Remove a song from queueOrder only (keep in pool). Used for rollback when MusicKit insert fails.
    func removingFromQueueOnly(id: String) -> QueueState {
        QueueState(
            songPool: songPool,
            queueOrder: queueOrder.filter { $0.id != id },
            playedIds: playedIds,
            currentIndex: currentIndex,
            algorithm: algorithm
        )
    }

    // MARK: - Queue Mutations

    /// Append a song to the end of the queue order (for adding during playback).
    func appendingToQueue(_ song: Song) -> QueueState {
        QueueState(
            songPool: songPool,
            queueOrder: queueOrder + [song],
            playedIds: playedIds,
            currentIndex: currentIndex,
            algorithm: algorithm
        )
    }

    /// Create a shuffled queue from the song pool.
    func shuffled(with algorithm: ShuffleAlgorithm? = nil) -> QueueState {
        let effectiveAlgorithm = algorithm ?? self.algorithm
        let shuffler = QueueShuffler(algorithm: effectiveAlgorithm)
        let shuffledSongs = shuffler.shuffle(songPool)

        return QueueState(
            songPool: songPool,
            queueOrder: shuffledSongs,
            playedIds: [],  // Reset played history on fresh shuffle
            currentIndex: 0,
            algorithm: effectiveAlgorithm
        )
    }

    /// Reshuffle upcoming songs while preserving current song and played history.
    func reshuffledUpcoming(with algorithm: ShuffleAlgorithm? = nil) -> QueueState {
        let effectiveAlgorithm = algorithm ?? self.algorithm

        // Get songs that haven't been played and aren't current
        let upcomingPool = songPool.filter { song in
            !playedIds.contains(song.id) && song.id != currentSongId
        }

        let shuffler = QueueShuffler(algorithm: effectiveAlgorithm)
        let shuffledUpcoming = shuffler.shuffle(upcomingPool)

        // Build new queue: current song + shuffled upcoming
        var newQueue: [Song] = []
        if let current = currentSong {
            newQueue.append(current)
        }
        newQueue.append(contentsOf: shuffledUpcoming)

        return QueueState(
            songPool: songPool,
            queueOrder: newQueue,
            playedIds: playedIds,
            currentIndex: 0,  // Current song is now at index 0
            algorithm: effectiveAlgorithm
        )
    }

    /// Advance to the next song.
    func advancedToNext() -> QueueState {
        guard hasNext else { return self }

        // Add current song to played history
        var newPlayedIds = playedIds
        if let currentId = currentSongId {
            newPlayedIds.insert(currentId)
        }

        return QueueState(
            songPool: songPool,
            queueOrder: queueOrder,
            playedIds: newPlayedIds,
            currentIndex: currentIndex + 1,
            algorithm: algorithm
        )
    }

    /// Go back to the previous song.
    func revertedToPrevious() -> QueueState {
        guard hasPrevious else { return self }

        // Remove current song from played history (going back)
        let previousSong = queueOrder[currentIndex - 1]
        var newPlayedIds = playedIds
        newPlayedIds.remove(previousSong.id)

        return QueueState(
            songPool: songPool,
            queueOrder: queueOrder,
            playedIds: newPlayedIds,
            currentIndex: currentIndex - 1,
            algorithm: algorithm
        )
    }

    /// Mark a song as played.
    func markingAsPlayed(id: String) -> QueueState {
        guard !playedIds.contains(id) else { return self }

        return QueueState(
            songPool: songPool,
            queueOrder: queueOrder,
            playedIds: playedIds.union([id]),
            currentIndex: currentIndex,
            algorithm: algorithm
        )
    }

    /// Clear played history (e.g., when starting fresh playback).
    func clearingPlayedHistory() -> QueueState {
        QueueState(
            songPool: songPool,
            queueOrder: queueOrder,
            playedIds: [],
            currentIndex: currentIndex,
            algorithm: algorithm
        )
    }

    // MARK: - Restoration

    /// Restore queue from persisted state.
    /// - Parameters:
    ///   - queueOrder: Persisted queue order as song IDs
    ///   - currentSongId: The song that was playing
    ///   - playedIds: Songs that had been played
    /// - Returns: Restored state, or nil if restoration fails
    ///
    /// Note: The queue is reordered so the current song is first. This is required
    /// because MusicKit's setQueue always starts from the first song in the array.
    func restored(
        queueOrder persistedOrder: [String],
        currentSongId: String?,
        playedIds persistedPlayedIds: Set<String>
    ) -> QueueState? {
        guard !songPool.isEmpty else { return nil }

        // Build lookup for valid songs
        let songById = Dictionary(uniqueKeysWithValues: songPool.map { ($0.id, $0) })

        // Filter queue to only songs that still exist in pool
        let validQueueSongs = persistedOrder.compactMap { songById[$0] }
        guard !validQueueSongs.isEmpty else { return nil }

        // Filter played IDs to only valid songs
        let validPlayedIds = persistedPlayedIds.filter { songById[$0] != nil }

        // Reorder queue so current song is first (MusicKit always starts from first song)
        let reorderedQueue: [Song]
        if let currentId = currentSongId,
           let currentIndex = validQueueSongs.firstIndex(where: { $0.id == currentId }) {
            // Rotate queue to start from current song
            let fromCurrentSong = Array(validQueueSongs[currentIndex...])
            let beforeCurrentSong = Array(validQueueSongs[..<currentIndex])
            reorderedQueue = fromCurrentSong + beforeCurrentSong
        } else {
            // Current song not found - use queue as-is
            reorderedQueue = validQueueSongs
        }

        return QueueState(
            songPool: songPool,
            queueOrder: reorderedQueue,
            playedIds: validPlayedIds,
            currentIndex: 0,  // Current song is now at index 0
            algorithm: algorithm
        )
    }

    // MARK: - Persistence Helpers

    /// Queue order as song IDs (for persistence).
    var queueOrderIds: [String] {
        queueOrder.map(\.id)
    }

    /// Whether there's state worth persisting.
    var hasRestorableState: Bool {
        !songPool.isEmpty && !queueOrder.isEmpty
    }
}

// MARK: - Equatable

extension QueueState {
    static func == (lhs: QueueState, rhs: QueueState) -> Bool {
        lhs.songPool.map(\.id) == rhs.songPool.map(\.id) &&
        lhs.queueOrder.map(\.id) == rhs.queueOrder.map(\.id) &&
        lhs.playedIds == rhs.playedIds &&
        lhs.currentIndex == rhs.currentIndex &&
        lhs.algorithm == rhs.algorithm
    }
}
