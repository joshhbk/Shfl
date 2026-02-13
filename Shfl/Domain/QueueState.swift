import Foundation

enum QueueDriftReason: String, CaseIterable, Hashable, Sendable {
    case countMismatch
    case duplicateQueueIDs
    case membershipMismatch

    var displayName: String {
        switch self {
        case .countMismatch: return "Count mismatch"
        case .duplicateQueueIDs: return "Duplicate queue IDs"
        case .membershipMismatch: return "Pool/queue membership mismatch"
        }
    }
}

struct QueueDriftDiagnostics: Equatable, Sendable {
    let isStale: Bool
    let reasons: Set<QueueDriftReason>
    let poolCount: Int
    let queueCount: Int
    let duplicateQueueIDs: [String]
    let missingFromQueue: [String]
    let missingFromPool: [String]
}

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
    /// Fast O(n) membership check without allocating full diagnostics.
    var isQueueStale: Bool {
        guard hasQueue else { return false }
        guard queueOrder.count == songPool.count else { return true }

        let poolIdSet = Set(songPool.map(\.id))
        var seen = Set<String>()
        for song in queueOrder {
            // Duplicate in queue or not in pool → stale
            guard poolIdSet.contains(song.id), seen.insert(song.id).inserted else {
                return true
            }
        }
        return false
    }

    /// Detailed invariant diagnostics for queue/pool drift.
    /// Only called when drift is detected and full details are needed for telemetry.
    var queueDriftDiagnostics: QueueDriftDiagnostics {
        guard hasQueue else {
            return QueueDriftDiagnostics(
                isStale: false,
                reasons: [],
                poolCount: songPool.count,
                queueCount: 0,
                duplicateQueueIDs: [],
                missingFromQueue: [],
                missingFromPool: []
            )
        }

        let queueIds = queueOrder.map(\.id)
        let poolIds = songPool.map(\.id)
        let queueIdSet = Set(queueIds)
        let poolIdSet = Set(poolIds)

        var reasons = Set<QueueDriftReason>()
        if queueIds.count != poolIds.count {
            reasons.insert(.countMismatch)
        }

        var seen = Set<String>()
        var duplicateQueueIDs: [String] = []
        for id in queueIds where !seen.insert(id).inserted {
            if !duplicateQueueIDs.contains(id) {
                duplicateQueueIDs.append(id)
            }
        }
        if !duplicateQueueIDs.isEmpty {
            reasons.insert(.duplicateQueueIDs)
        }

        let missingFromQueue = poolIds.filter { !queueIdSet.contains($0) }
        let missingFromPool = queueIds.filter { !poolIdSet.contains($0) }
        if !missingFromQueue.isEmpty || !missingFromPool.isEmpty {
            reasons.insert(.membershipMismatch)
        }

        return QueueDriftDiagnostics(
            isStale: !reasons.isEmpty,
            reasons: reasons,
            poolCount: poolIds.count,
            queueCount: queueIds.count,
            duplicateQueueIDs: duplicateQueueIDs,
            missingFromQueue: missingFromQueue,
            missingFromPool: missingFromPool
        )
    }

    /// Invalidate the queue while preserving the song pool.
    /// Used when the algorithm changes while not playing.
    func invalidatingQueue(using algorithm: ShuffleAlgorithm? = nil) -> QueueState {
        let effectiveAlgorithm = algorithm ?? self.algorithm
        return QueueState(
            songPool: songPool,
            queueOrder: [],
            playedIds: [],
            currentIndex: 0,
            algorithm: effectiveAlgorithm
        )
    }

    // MARK: - Query Methods

    /// Check if a song is in the pool.
    func containsSong(id: String) -> Bool {
        songPool.contains(where: { $0.id == id })
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
        guard !containsSong(id: song.id) else { return self }

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
        let existingIds = Set(songPool.map(\.id))
        let uniqueNewSongs = songs.filter { !existingIds.contains($0.id) }
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

    /// Align current index to an observed song ID while preserving queue order/history.
    func settingCurrentSong(id: String) -> QueueState {
        guard let newIndex = queueOrder.firstIndex(where: { $0.id == id }) else { return self }
        guard newIndex != currentIndex else { return self }

        return QueueState(
            songPool: songPool,
            queueOrder: queueOrder,
            playedIds: playedIds,
            currentIndex: newIndex,
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
    func reshuffledUpcoming(
        with algorithm: ShuffleAlgorithm? = nil,
        preferredCurrentSongId: String? = nil
    ) -> QueueState {
        let effectiveAlgorithm = algorithm ?? self.algorithm
        let preferredCurrentSongId = preferredCurrentSongId ?? currentSongId
        let reconciled = reconcilingQueue(preferredCurrentSongId: preferredCurrentSongId)
        guard let current = reconciled.currentSong else {
            // If current context is invalid, fall back to a full fresh shuffle.
            return reconciled.shuffled(with: effectiveAlgorithm)
        }

        // Preserve already-played songs ahead of current and reshuffle only upcoming.
        let playedPrefix = Array(reconciled.queueOrder.prefix(reconciled.currentIndex))
        let playedPrefixIds = Set(playedPrefix.map(\.id))
        let upcomingPool = reconciled.songPool.filter { song in
            !playedPrefixIds.contains(song.id) && song.id != current.id
        }

        let shuffler = QueueShuffler(algorithm: effectiveAlgorithm)
        let shuffledUpcoming = shuffler.shuffle(upcomingPool)
        let newQueue = playedPrefix + [current] + shuffledUpcoming

        return QueueState(
            songPool: reconciled.songPool,
            queueOrder: newQueue,
            playedIds: reconciled.playedIds,
            currentIndex: playedPrefix.count,
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
    /// Note: Queue ordering is preserved exactly as persisted so replaying the app
    /// keeps played/current/upcoming continuity across launches.
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

        // Keep persisted order intact and locate current within that queue.
        let restoredIndex = currentSongId.flatMap { currentId in
            validQueueSongs.firstIndex(where: { $0.id == currentId })
        } ?? 0

        let restored = QueueState(
            songPool: songPool,
            queueOrder: validQueueSongs,
            playedIds: validPlayedIds,
            currentIndex: restoredIndex,
            algorithm: algorithm
        )

        // Repair only stale historical persisted states that omitted part of the pool.
        if restored.isQueueStale {
            return restored.reconcilingQueue(preferredCurrentSongId: currentSongId)
        }
        return restored
    }

    // MARK: - Invariant Repair

    /// Deterministically repair queue drift while preserving current-song and played-song context.
    /// This keeps played songs before current and appends any missing songs from pool order.
    func reconcilingQueue(preferredCurrentSongId: String? = nil) -> QueueState {
        guard hasQueue else { return self }

        let poolSongsById = Dictionary(uniqueKeysWithValues: songPool.map { ($0.id, $0) })
        let poolOrderIds = songPool.map(\.id)

        // Keep only queue IDs that still exist in pool, preserving first occurrence order.
        var seen = Set<String>()
        let normalizedQueueIds = queueOrder.map(\.id).filter { id in
            guard poolSongsById[id] != nil else { return false }
            guard !seen.contains(id) else { return false }
            seen.insert(id)
            return true
        }

        let preferredCurrentId = preferredCurrentSongId.flatMap { poolSongsById[$0] != nil ? $0 : nil }
        let fallbackCurrentId = currentSongId.flatMap { poolSongsById[$0] != nil ? $0 : nil }
        let currentId = preferredCurrentId ?? fallbackCurrentId ?? normalizedQueueIds.first ?? poolOrderIds.first

        // Keep played songs in deterministic order before current.
        var playedPrefixIds = normalizedQueueIds.filter { id in
            playedIds.contains(id) && id != currentId
        }
        let playedPrefixSet = Set(playedPrefixIds)
        let missingPlayedIds = poolOrderIds.filter { id in
            playedIds.contains(id) && id != currentId && !playedPrefixSet.contains(id)
        }
        playedPrefixIds.append(contentsOf: missingPlayedIds)

        // Keep existing unplayed ordering for upcoming songs, then append missing ones in pool order.
        var upcomingIds = normalizedQueueIds.filter { id in
            id != currentId && !playedIds.contains(id)
        }
        var includedIds = Set(playedPrefixIds)
        if let currentId { includedIds.insert(currentId) }
        includedIds.formUnion(upcomingIds)

        let missingUpcomingIds = poolOrderIds.filter { id in
            id != currentId && !includedIds.contains(id)
        }
        upcomingIds.append(contentsOf: missingUpcomingIds)

        var repairedIds = playedPrefixIds
        if let currentId { repairedIds.append(currentId) }
        repairedIds.append(contentsOf: upcomingIds)

        let repairedQueue = repairedIds.compactMap { poolSongsById[$0] }
        guard !repairedQueue.isEmpty else { return self }

        let repairedCurrentIndex = currentId.flatMap { id in
            repairedQueue.firstIndex(where: { $0.id == id })
        } ?? 0

        let repairedPlayedIds = Set(playedIds.filter { id in
            poolSongsById[id] != nil && id != currentId
        })

        return QueueState(
            songPool: songPool,
            queueOrder: repairedQueue,
            playedIds: repairedPlayedIds,
            currentIndex: repairedCurrentIndex,
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
        lhs.currentIndex == rhs.currentIndex &&
        lhs.algorithm == rhs.algorithm &&
        lhs.playedIds == rhs.playedIds &&
        lhs.songPool == rhs.songPool &&
        lhs.queueOrder == rhs.queueOrder
    }
}
