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
    @ObservationIgnored private var stateTask: Task<Void, Never>?

    /// Single source of truth for queue state
    private(set) var queueState: QueueState = .empty

    /// Current playback state from MusicKit
    private(set) var playbackState: PlaybackState = .empty

    /// Track last observed song for history updates
    @ObservationIgnored private var lastObservedSongId: String?

    /// Flag to suppress history updates during multi-step operations
    @ObservationIgnored private var suppressHistoryUpdates = false

    // MARK: - Computed Properties (for compatibility)

    var songs: [Song] { queueState.songPool }
    var songCount: Int { queueState.songCount }
    var allSongs: [Song] { queueState.songPool }
    var capacity: Int { QueueState.maxSongs }
    var remainingCapacity: Int { queueState.remainingCapacity }

    /// Debug: The last shuffled queue order (for verifying shuffle algorithms)
    var lastShuffledQueue: [Song] { queueState.queueOrder }

    /// Debug: The algorithm used for the last shuffle
    var lastUsedAlgorithm: ShuffleAlgorithm { queueState.algorithm }

    /// Exposed for testing only
    var playedSongIdsForTesting: Set<String> { queueState.playedIds }

    // MARK: - Queue State Exposure (for persistence)

    /// Current queue order as song IDs (for persistence)
    var currentQueueOrder: [String] { queueState.queueOrderIds }

    /// Currently played song IDs (for persistence)
    var currentPlayedSongIds: Set<String> { queueState.playedIds }

    /// Whether there's a valid state that could be restored
    var hasRestorableState: Bool { queueState.hasRestorableState }

    // MARK: - Initialization

    init(musicService: MusicService) {
        self.musicService = musicService
        observePlaybackState()
    }

    deinit {
        stateTask?.cancel()
    }

    // MARK: - Playback State Observation

    private func observePlaybackState() {
        stateTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await state in self.musicService.playbackStateStream {
                self.handlePlaybackStateChange(state)
            }
        }
    }

    private func handlePlaybackStateChange(_ newState: PlaybackState) {
        // If the queue is empty, ignore any MusicKit states with songs (they're stale)
        if queueState.isEmpty && newState.currentSong != nil {
            playbackState = .empty
            lastObservedSongId = nil
            return
        }

        // MusicKit returns catalog IDs for queue entries, but our song pool uses library IDs.
        // Look up the song in our pool by title+artist to get the correct library ID,
        // but keep MusicKit's fresh artwork URL.
        let resolvedState: PlaybackState
        let resolvedSongId: String?

        if let musicKitSong = newState.currentSong,
           let poolSong = queueState.songPool.first(where: { $0.title == musicKitSong.title && $0.artist == musicKitSong.artist }) {
            // Found matching song in pool - use pool's ID but keep MusicKit's artwork
            resolvedSongId = poolSong.id
            let mergedSong = Song(
                id: poolSong.id,
                title: musicKitSong.title,
                artist: musicKitSong.artist,
                albumTitle: musicKitSong.albumTitle,
                artworkURL: musicKitSong.artworkURL,
                playCount: musicKitSong.playCount,
                lastPlayedDate: musicKitSong.lastPlayedDate
            )
            switch newState {
            case .playing:
                resolvedState = .playing(mergedSong)
            case .paused:
                resolvedState = .paused(mergedSong)
            case .loading:
                resolvedState = .loading(mergedSong)
            default:
                resolvedState = newState
            }
        } else {
            // No match in pool - use MusicKit's data as-is
            resolvedSongId = newState.currentSongId
            resolvedState = newState
        }

        // Song changed - add previous to history (unless suppressed during operations)
        if !suppressHistoryUpdates,
           let lastId = lastObservedSongId,
           lastId != resolvedSongId {
            queueState = queueState.markingAsPlayed(id: lastId)
        }
        lastObservedSongId = resolvedSongId

        // Clear history on stop/empty/error
        switch resolvedState {
        case .stopped, .empty, .error:
            queueState = queueState.clearingPlayedHistory()
            lastObservedSongId = nil
        default:
            break
        }

        playbackState = resolvedState
    }

    // MARK: - Algorithm Change

    /// Called when shuffle algorithm changes. Views should call this via onChange(of: appSettings.shuffleAlgorithm).
    func reshuffleWithNewAlgorithm(_ algorithm: ShuffleAlgorithm) async {
        guard !queueState.isEmpty else { return }

        // If not actively playing, invalidate the queue so next play() rebuilds with the new algorithm
        guard playbackState.isActive else {
            print("🎲 Algorithm changed to \(algorithm.displayName) while not active, invalidating queue")
            queueState = queueState.invalidatingQueue()
            return
        }

        print("🎲 Algorithm changed to \(algorithm.displayName), reshuffling...")

        guard let currentSong = playbackState.currentSong,
              queueState.containsSong(id: currentSong.id) else {
            print("🎲 No current song found, skipping reshuffle")
            return
        }

        // Update queue state with reshuffled upcoming songs
        queueState = queueState.reshuffledUpcoming(with: algorithm)

        print("🎲 New queue order: \(queueState.queueOrder.map { "\($0.title) by \($0.artist)" })")

        do {
            // Get upcoming songs (exclude current which is at index 0 after reshuffle)
            let upcomingSongs = Array(queueState.queueOrder.dropFirst())
            try await musicService.replaceUpcomingQueue(with: upcomingSongs, currentSong: currentSong)
            print("🎲 replaceUpcomingQueue succeeded")
        } catch {
            print("🎲 replaceUpcomingQueue FAILED: \(error)")
        }
    }

    // MARK: - Song Management

    func addSong(_ song: Song) throws {
        print("➕ addSong(\(song.title)): current songCount=\(queueState.songCount), queueOrder=\(queueState.queueOrder.count), isActive=\(playbackState.isActive)")
        guard let newState = queueState.addingSong(song) else {
            print("➕ addSong: capacity reached!")
            throw ShufflePlayerError.capacityReached
        }

        // Check if it was actually added (not a duplicate)
        guard newState.songCount > queueState.songCount else {
            print("➕ addSong: already exists, skipping")
            return // Already added
        }

        queueState = newState
        print("➕ addSong: added to pool, new songCount=\(queueState.songCount)")

        // If playing, also add to our internal queue order and MusicKit queue
        if playbackState.isActive && queueState.hasQueue {
            // Add to our internal queue order
            queueState = queueState.appendingToQueue(song)
            print("➕ addSong: appended to queueOrder, now \(queueState.queueOrder.count) songs")

            // Insert into MusicKit queue (with rollback on failure)
            Task {
                do {
                    try await musicService.insertIntoQueue(songs: [song])
                    print("🎵 Successfully inserted \(song.title) into MusicKit queue")
                } catch {
                    // Rollback: remove from queue order since MusicKit doesn't have it
                    queueState = queueState.removingFromQueueOnly(id: song.id)
                    print("⚠️ Rolled back \(song.title) from queue after insert failure: \(error)")
                }
            }
        } else {
            print("➕ addSong: playback not active or no queue yet, song only added to pool")
        }
    }

    func addSongs(_ newSongs: [Song]) throws {
        guard let newState = queueState.addingSongs(newSongs) else {
            throw ShufflePlayerError.capacityReached
        }
        queueState = newState
        // Don't rebuild queue during initial load - not playing yet
    }

    /// Add songs and reshuffle queue if playing (interleaves new songs throughout upcoming queue)
    func addSongsWithQueueRebuild(_ newSongs: [Song]) async throws {
        print("🔍 addSongsWithQueueRebuild: Received \(newSongs.count) songs")

        guard let newState = queueState.addingSongs(newSongs) else {
            print("🔍 addSongsWithQueueRebuild: Capacity exceeded!")
            throw ShufflePlayerError.capacityReached
        }

        let addedCount = newState.songCount - queueState.songCount
        print("🔍 addSongsWithQueueRebuild: \(addedCount) unique after filtering")

        queueState = newState
        print("🔍 addSongsWithQueueRebuild: Added to internal list, playbackState.isActive = \(playbackState.isActive)")

        // If playing, reshuffle to interleave new songs throughout upcoming queue
        if playbackState.isActive {
            guard let currentSong = playbackState.currentSong,
                  queueState.containsSong(id: currentSong.id) else {
                print("🔍 addSongsWithQueueRebuild: No current song, skipping reshuffle")
                return
            }

            // Read shuffle algorithm from UserDefaults
            let algorithm = currentAlgorithm()

            // Reshuffle upcoming songs (this excludes played songs and current song)
            queueState = queueState.reshuffledUpcoming(with: algorithm)

            print("🎵 Reshuffling with \(addedCount) new songs interleaved")

            do {
                let upcomingSongs = Array(queueState.queueOrder.dropFirst())
                try await musicService.replaceUpcomingQueue(with: upcomingSongs, currentSong: currentSong)
                print("🎵 Successfully reshuffled queue with \(upcomingSongs.count) upcoming songs")
            } catch {
                print("🎵 Failed to reshuffle queue: \(error)")
            }
        }
        print("🔍 addSongsWithQueueRebuild: Complete")
    }

    func removeSong(id: String) async {
        let isRemovingCurrentSong = playbackState.currentSongId == id
        queueState = queueState.removingSong(id: id)

        // Update MusicKit queue if actively playing
        guard playbackState.isActive else { return }

        if isRemovingCurrentSong {
            // Removing current song - skip to next
            do {
                try await musicService.skipToNext()
                print("🎵 Skipped to next after removing current song")
            } catch {
                print("🎵 Failed to skip after removing current song: \(error)")
            }
        } else if let currentSong = playbackState.currentSong,
                  queueState.containsSong(id: currentSong.id) {
            // Removing upcoming song - rebuild queue without it
            let upcomingSongs = queueState.queueOrder.filter { $0.id != currentSong.id }
            do {
                try await musicService.replaceUpcomingQueue(with: upcomingSongs, currentSong: currentSong)
                print("🎵 Removed song \(id) from MusicKit queue")
            } catch {
                print("🎵 Failed to remove song from MusicKit queue: \(error)")
            }
        }
    }

    func removeAllSongs() async {
        print("🗑️ removeAllSongs() called: had \(queueState.songCount) songs, queueOrder had \(queueState.queueOrder.count)")
        queueState = queueState.cleared()
        lastObservedSongId = nil

        // Stop MusicKit playback so it doesn't continue with stale queue
        await musicService.pause()
        playbackState = .empty

        print("🗑️ removeAllSongs() complete: now \(queueState.songCount) songs, queueOrder has \(queueState.queueOrder.count)")
    }

    func containsSong(id: String) -> Bool {
        queueState.containsSong(id: id)
    }

    // MARK: - Queue Preparation

    func prepareQueue(algorithm: ShuffleAlgorithm? = nil) async throws {
        guard !queueState.isEmpty else { return }

        let effectiveAlgorithm = algorithm ?? currentAlgorithm()

        print("🎲 prepareQueue: songPool has \(queueState.songCount) songs")

        // Shuffle the queue
        queueState = queueState.shuffled(with: effectiveAlgorithm)
        print("🎲 Prepared queue with algorithm: \(effectiveAlgorithm.displayName)")
        print("🎲 prepareQueue: queueOrder now has \(queueState.queueOrder.count) songs")

        try await musicService.setQueue(songs: queueState.queueOrder)
    }

    // MARK: - Playback Control

    func play() async throws {
        print("▶️ play() called: isEmpty=\(queueState.isEmpty), hasQueue=\(queueState.hasQueue), isQueueStale=\(queueState.isQueueStale), songCount=\(queueState.songCount)")
        guard !queueState.isEmpty else {
            print("▶️ play() early return: queue is empty")
            return
        }

        // Clear played history for fresh playback
        queueState = queueState.clearingPlayedHistory()
        lastObservedSongId = nil

        if !queueState.hasQueue || queueState.isQueueStale {
            print("▶️ play() queue needs (re)build, preparing...")
            try await prepareQueue()
            // Emit loading with the actual first song from shuffled queue
            if let firstSong = queueState.currentSong {
                playbackState = .loading(firstSong)
            }
            print("▶️ play() queue prepared, order has \(queueState.queueOrder.count) songs")
        } else {
            print("▶️ play() queue already exists with \(queueState.queueOrder.count) songs")
        }

        try await musicService.play()
        print("▶️ play() complete")
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
            // If we have songs but no queue (e.g., after clear + re-add), build queue first
            if !queueState.isEmpty && !queueState.hasQueue {
                print("▶️ togglePlayback: paused but no queue, calling play() to rebuild")
                try await play()
            } else {
                try await musicService.play()
            }
        case .loading:
            // Do nothing while loading
            break
        case .error:
            // Try to play again
            try await play()
        }
    }

    // MARK: - Queue Restoration

    /// Restores the queue from persisted state.
    /// - Parameters:
    ///   - queueOrder: Array of song IDs representing the queue order
    ///   - currentSongId: The ID of the song that was playing
    ///   - playedIds: Set of song IDs that have been played
    ///   - playbackPosition: The position in seconds to seek to
    /// - Returns: True if restoration was successful, false if a fresh shuffle is needed
    func restoreQueue(
        queueOrder: [String],
        currentSongId: String?,
        playedIds: Set<String>,
        playbackPosition: TimeInterval
    ) async -> Bool {
        print("🔄 restoreQueue called: songs=\(queueState.songCount), queueOrder=\(queueOrder.count), currentSongId=\(currentSongId ?? "nil")")

        guard !queueState.isEmpty else {
            print("🔄 restoreQueue: No songs in pool, returning false")
            return false
        }

        // Attempt to restore from persisted state
        guard let restoredState = queueState.restored(
            queueOrder: queueOrder,
            currentSongId: currentSongId,
            playedIds: playedIds
        ) else {
            print("🔄 restoreQueue: Failed to restore state, returning false")
            return false
        }

        // Apply restored state
        queueState = restoredState
        lastObservedSongId = queueState.currentSongId
        print("🔄 restoreQueue: Restored state with \(queueState.queueOrder.count) songs, current=\(queueState.currentSong?.title ?? "none")")

        // Suppress history updates during the restore sequence
        suppressHistoryUpdates = true
        defer { suppressHistoryUpdates = false }

        // Set the queue in MusicKit
        do {
            print("🔄 restoreQueue: Setting queue with \(queueState.queueOrder.count) songs")
            try await musicService.setQueue(songs: queueState.queueOrder)

            // Brief play to load the song (required for seek to work and metadata to load)
            print("🔄 restoreQueue: Playing briefly to load song...")
            try await musicService.play()

            // Seek to saved position
            let clampedPosition = max(0, playbackPosition)
            if clampedPosition > 0 {
                print("🔄 restoreQueue: Seeking to position \(clampedPosition)")
                musicService.seek(to: clampedPosition)
            }

            // Pause - user will see restored state
            print("🔄 restoreQueue: Pausing...")
            await musicService.pause()

            print("🔄 restoreQueue: Success!")
            return true
        } catch {
            print("🔄 restoreQueue: Failed to set queue: \(error)")
            return false
        }
    }

    /// Resumes playback after restoration (call after restoreQueue succeeds)
    func resumeAfterRestore() async throws {
        try await musicService.play()
    }

    // MARK: - Helpers

    private func currentAlgorithm() -> ShuffleAlgorithm {
        let algorithmRaw = UserDefaults.standard.string(forKey: "shuffleAlgorithm")
            ?? ShuffleAlgorithm.noRepeat.rawValue
        return ShuffleAlgorithm(rawValue: algorithmRaw) ?? .noRepeat
    }
}
