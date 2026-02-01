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

    // MARK: - Queue State Exposure (for persistence)

    /// Current queue order as song IDs (for persistence)
    var currentQueueOrder: [String] {
        lastShuffledQueue.map(\.id)
    }

    /// Currently played song IDs (for persistence)
    var currentPlayedSongIds: Set<String> {
        playedSongIds
    }

    /// Whether there's a valid state that could be restored
    var hasRestorableState: Bool {
        !songs.isEmpty && !lastShuffledQueue.isEmpty
    }

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
        // MusicKit returns catalog IDs for queue entries, but our song pool uses library IDs.
        // Look up the song in our pool by title+artist to get the correct library ID,
        // but keep MusicKit's fresh artwork URL.
        let resolvedState: PlaybackState
        let resolvedSongId: String?

        if let musicKitSong = newState.currentSong,
           let poolSong = songs.first(where: { $0.title == musicKitSong.title && $0.artist == musicKitSong.artist }) {
            // Found matching song in pool - use pool's ID but keep MusicKit's artwork
            resolvedSongId = poolSong.id
            let mergedSong = Song(
                id: poolSong.id,
                title: musicKitSong.title,
                artist: musicKitSong.artist,
                albumTitle: musicKitSong.albumTitle,
                artworkURL: musicKitSong.artworkURL,  // Keep MusicKit's fresh artwork
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

        // Song changed - add previous to history
        if let lastId = lastObservedSongId, lastId != resolvedSongId {
            playedSongIds.insert(lastId)
        }
        lastObservedSongId = resolvedSongId

        // Clear history on stop/empty/error
        switch resolvedState {
        case .stopped, .empty, .error:
            playedSongIds.removeAll()
            lastObservedSongId = nil
        default:
            break
        }

        playbackState = resolvedState
    }

    private func rebuildQueueIfPlaying() async {
        guard playbackState.isActive else { return }

        let currentSongId = playbackState.currentSongId

        // Filter out played songs AND currently playing song
        let upcomingSongs = songs.filter { song in
            !playedSongIds.contains(song.id) && song.id != currentSongId
        }

        // Read shuffle algorithm from UserDefaults
        let algorithmRaw = UserDefaults.standard.string(forKey: "shuffleAlgorithm")
            ?? ShuffleAlgorithm.noRepeat.rawValue
        let algorithm = ShuffleAlgorithm(rawValue: algorithmRaw) ?? .noRepeat

        // Apply shuffle
        let shuffler = QueueShuffler(algorithm: algorithm)
        let shuffledUpcoming = shuffler.shuffle(upcomingSongs)

        // Build queue: current song first, then shuffled upcoming
        var newQueue: [Song] = []
        if let currentId = currentSongId,
           let currentSong = songs.first(where: { $0.id == currentId }) {
            newQueue.append(currentSong)
        }
        newQueue.append(contentsOf: shuffledUpcoming)

        guard !newQueue.isEmpty else { return }

        lastShuffledQueue = newQueue
        lastUsedAlgorithm = algorithm

        // Check if currently playing (vs paused/loading)
        let isCurrentlyPlaying = playbackState.isPlaying

        do {
            try await musicService.setQueue(songs: newQueue)

            // Only call play() if we removed the current song (need to start next song)
            // If still playing the same song, don't call play() - it would restart the song
            let currentSongWasRemoved = currentSongId != nil &&
                !songs.contains(where: { $0.id == currentSongId })

            if currentSongWasRemoved || !isCurrentlyPlaying {
                try await musicService.play()
            }
        } catch {
            print("🎲 rebuildQueueIfPlaying failed: \(error)")
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

        // If playing, insert into existing queue without disruption
        if playbackState.isActive {
            // Update debug queue to show the new song
            lastShuffledQueue.append(song)

            Task {
                do {
                    try await musicService.insertIntoQueue(songs: [song])
                    print("🎵 Successfully inserted \(song.title) into queue")
                } catch {
                    print("🎵 Failed to insert \(song.title): \(error)")
                }
            }
        }
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

    /// Add songs and insert into queue if playing (for autofill efficiency)
    func addSongsWithQueueRebuild(_ newSongs: [Song]) async throws {
        let uniqueNewSongs = newSongs.filter { !songIds.contains($0.id) }

        let availableCapacity = Self.maxSongs - songs.count
        guard uniqueNewSongs.count <= availableCapacity else {
            throw ShufflePlayerError.capacityReached
        }

        songs.append(contentsOf: uniqueNewSongs)
        songIds.formUnion(uniqueNewSongs.map(\.id))
        queueValid = false

        // If playing, insert songs into existing queue without disruption
        if playbackState.isActive {
            // Update debug queue to show new songs
            lastShuffledQueue.append(contentsOf: uniqueNewSongs)

            do {
                try await musicService.insertIntoQueue(songs: uniqueNewSongs)
                print("🎵 Successfully inserted \(uniqueNewSongs.count) songs into queue")
            } catch {
                print("🎵 Failed to insert songs: \(error)")
            }
        }
    }

    func removeSong(id: String) {
        let isCurrentSong = playbackState.currentSongId == id

        songs.removeAll { $0.id == id }
        songIds.remove(id)
        queueValid = false

        // If we removed the currently playing song, skip to next
        if isCurrentSong && playbackState.isActive {
            Task {
                try? await musicService.skipToNext()
            }
        }
        // Note: Songs removed that aren't current will still be in MusicKit's queue
        // They'll be skipped when handlePlaybackStateChange detects they're not in our songs list
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
        print("🔄 restoreQueue called: songs=\(songs.count), queueOrder=\(queueOrder.count), currentSongId=\(currentSongId ?? "nil")")

        guard !songs.isEmpty else {
            print("🔄 restoreQueue: No songs in pool, returning false")
            return false
        }

        // Build song lookup for O(1) access
        let songById = Dictionary(uniqueKeysWithValues: songs.map { ($0.id, $0) })

        // Filter queue to only songs that still exist in the pool
        let validQueueSongs = queueOrder.compactMap { songById[$0] }
        print("🔄 restoreQueue: validQueueSongs=\(validQueueSongs.count)")

        // If queue is empty after filtering, need fresh shuffle
        guard !validQueueSongs.isEmpty else {
            print("🔄 restoreQueue: No valid queue songs, returning false")
            return false
        }

        // Restore played history (only for songs still in pool)
        let validPlayedIds = playedIds.filter { songById[$0] != nil }
        playedSongIds = validPlayedIds

        // Reorder queue so current song is first (setQueue always starts from first song)
        let effectiveQueue: [Song]
        let effectiveCurrentSong: Song?

        // Debug: log what we're searching for
        print("🔄 restoreQueue: Looking for currentSongId=\(currentSongId ?? "nil") in \(validQueueSongs.count) songs")
        if let currentId = currentSongId {
            let matchingSongs = validQueueSongs.filter { $0.id == currentId }
            print("🔄 restoreQueue: Found \(matchingSongs.count) matching songs")
            if matchingSongs.isEmpty {
                // Log first few song IDs to see what we have
                let sampleIds = validQueueSongs.prefix(5).map { $0.id }
                print("🔄 restoreQueue: Sample song IDs in queue: \(sampleIds)")
            }
        }

        if let currentId = currentSongId,
           let currentIndex = validQueueSongs.firstIndex(where: { $0.id == currentId }) {
            // Current song exists - reorder queue to start from it
            let fromCurrentSong = Array(validQueueSongs[currentIndex...])
            let beforeCurrentSong = Array(validQueueSongs[..<currentIndex])
            effectiveQueue = fromCurrentSong + beforeCurrentSong
            effectiveCurrentSong = validQueueSongs[currentIndex]
            lastObservedSongId = currentId
            print("🔄 restoreQueue: Reordered queue to start at \(effectiveCurrentSong?.title ?? "unknown") (index \(currentIndex))")
        } else {
            // Current song missing - start with first available from queue
            effectiveQueue = validQueueSongs
            effectiveCurrentSong = validQueueSongs.first
            lastObservedSongId = effectiveCurrentSong?.id
            print("🔄 restoreQueue: Current song not found, starting from first song: \(effectiveCurrentSong?.title ?? "unknown") (id=\(effectiveCurrentSong?.id ?? "nil"))")
        }

        // Update debug state
        lastShuffledQueue = effectiveQueue
        // Read shuffle algorithm from UserDefaults for lastUsedAlgorithm
        let algorithmRaw = UserDefaults.standard.string(forKey: "shuffleAlgorithm")
            ?? ShuffleAlgorithm.noRepeat.rawValue
        lastUsedAlgorithm = ShuffleAlgorithm(rawValue: algorithmRaw) ?? .noRepeat

        // Set the queue in MusicKit
        do {
            print("🔄 restoreQueue: Setting queue with \(effectiveQueue.count) songs, first=\(effectiveQueue.first?.title ?? "none")")
            try await musicService.setQueue(songs: effectiveQueue)
            queueValid = true

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
}
