import Foundation

enum ShufflePlayerError: Error, Equatable {
    case capacityReached
    case notAuthorized
    case playbackFailed(String)
}

struct QueueDriftEvent: Equatable, Sendable, Identifiable {
    let id = UUID()
    let timestamp: Date
    let trigger: String
    let reasons: [QueueDriftReason]
    let poolCount: Int
    let queueCount: Int
    let duplicateCount: Int
    let missingFromQueueCount: Int
    let missingFromPoolCount: Int
    let currentSongId: String?
    let preferredCurrentSongId: String?
    let repaired: Bool
}

struct QueueDriftTelemetry: Equatable, Sendable {
    var detections: Int = 0
    var reconciliations: Int = 0
    var unrepairedDetections: Int = 0
    var detectionsByTrigger: [String: Int] = [:]
    var detectionsByReason: [QueueDriftReason: Int] = [:]
    var recentEvents: [QueueDriftEvent] = []
}

@MainActor
final class PlaybackCoordinator {
    private let player: ShufflePlayer
    private let appSettings: AppSettings

    /// Serializes command execution without manual continuation management.
    private var commandQueue: Task<Void, Never> = Task { }

    init(player: ShufflePlayer, appSettings: AppSettings) {
        self.player = player
        self.appSettings = appSettings
    }

    private func enqueue<T>(_ operation: @escaping @MainActor () async throws -> T) async throws -> T {
        let previous = self.commandQueue
        let task = Task<T, Error> { @MainActor in
            await previous.value
            return try await operation()
        }
        self.commandQueue = Task {
            _ = await task.result
        }
        return try await task.value
    }

    private func enqueue<T>(_ operation: @escaping @MainActor () async -> T) async -> T {
        let previous = self.commandQueue
        let task = Task<T, Never> { @MainActor in
            await previous.value
            return await operation()
        }
        self.commandQueue = Task {
            _ = await task.value
        }
        return await task.value
    }

    func seedSongs(_ songs: [Song]) async throws {
        try await enqueue { [self] in
            try self.player.addSongs(songs)
        }
    }

    func prepareQueue() async throws {
        try await enqueue { [self] in
            try await self.player.prepareQueue(algorithm: self.appSettings.shuffleAlgorithm)
        }
    }

    func play() async throws {
        try await enqueue { [self] in
            try await self.player.play(algorithm: self.appSettings.shuffleAlgorithm)
        }
    }

    func pause() async {
        await enqueue { [self] in
            await self.player.pause()
        }
    }

    func togglePlayback() async throws {
        try await enqueue { [self] in
            try await self.player.togglePlayback(algorithm: self.appSettings.shuffleAlgorithm)
        }
    }

    func skipToNext() async throws {
        try await enqueue { [self] in
            try await self.player.skipToNext()
        }
    }

    func restartOrSkipToPrevious() async throws {
        try await enqueue { [self] in
            try await self.player.restartOrSkipToPrevious()
        }
    }

    func addSong(_ song: Song) async throws {
        try await enqueue { [self] in
            try await self.player.addSong(song)
        }
    }

    func addSongsWithQueueRebuild(_ songs: [Song]) async throws {
        try await enqueue { [self] in
            try await self.player.addSongsWithQueueRebuild(songs, algorithm: self.appSettings.shuffleAlgorithm)
        }
    }

    func removeSong(id: String) async {
        await enqueue { [self] in
            await self.player.removeSong(id: id)
        }
    }

    func removeAllSongs() async {
        await enqueue { [self] in
            await self.player.removeAllSongs()
        }
    }

    func reshuffleAlgorithm(_ algorithm: ShuffleAlgorithm) async {
        await enqueue { [self] in
            await self.player.reshuffleWithNewAlgorithm(algorithm)
        }
    }

    func restoreSession(
        queueOrder: [String],
        currentSongId: String?,
        playedIds: Set<String>,
        playbackPosition: TimeInterval
    ) async -> Bool {
        await enqueue { [self] in
            await self.player.restoreSession(
                queueOrder: queueOrder,
                currentSongId: currentSongId,
                playedIds: playedIds,
                playbackPosition: playbackPosition
            )
        }
    }
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

    /// Diagnostics for queue drift detection and reconciliation.
    private(set) var queueDriftTelemetry = QueueDriftTelemetry()

    /// Track last observed song for history updates
    @ObservationIgnored private var lastObservedSongId: String?

    /// Flag to suppress history updates during multi-step operations
    @ObservationIgnored private var suppressHistoryUpdates = false

    /// Deferred restore seek that is applied on first explicit user play.
    @ObservationIgnored private var pendingRestoreSeek: (songId: String, position: TimeInterval)?

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
        // MusicKit can emit .stopped while a queue/current entry still exists after restore.
        // Preserve the visible "current song loaded but not playing" state in that case.
        let normalizedState: PlaybackState
        if case .stopped = newState,
           let current = queueState.currentSong,
           suppressHistoryUpdates {
            normalizedState = .paused(current)
        } else {
            normalizedState = newState
        }

        // If the queue is empty, ignore any MusicKit states with songs (they're stale)
        if queueState.isEmpty && normalizedState.currentSong != nil {
            playbackState = .empty
            lastObservedSongId = nil
            return
        }

        // Resolve IDs in a deterministic order:
        // 1. Exact ID match
        // 2. Metadata fallback (title + artist + album)
        let resolvedState: PlaybackState
        let resolvedSongId: String?

        if let musicKitSong = normalizedState.currentSong,
           let poolSong = queueState.songPool.first(where: { $0.id == musicKitSong.id }) ??
            queueState.songPool.first(where: {
                $0.title == musicKitSong.title &&
                $0.artist == musicKitSong.artist &&
                $0.albumTitle == musicKitSong.albumTitle
            }) {
            // Found a stable mapping in the pool. Keep MusicKit artwork freshness.
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
            switch normalizedState {
            case .playing:
                resolvedState = .playing(mergedSong)
            case .paused:
                resolvedState = .paused(mergedSong)
            case .loading:
                resolvedState = .loading(mergedSong)
            default:
                resolvedState = normalizedState
            }
        } else {
            // No match in pool - use MusicKit's data as-is
            resolvedSongId = normalizedState.currentSongId
            resolvedState = normalizedState
        }

        if let resolvedSongId {
            queueState = queueState.settingCurrentSong(id: resolvedSongId)
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

        reconcileQueueIfNeeded(reason: "playback-state-change", preferredCurrentSongId: resolvedSongId)

        if case .playing = resolvedState,
           let pendingSeek = pendingRestoreSeek,
           let resolvedSongId,
           pendingSeek.songId == resolvedSongId {
            pendingRestoreSeek = nil
            musicService.seek(to: pendingSeek.position)
        }

        playbackState = resolvedState
    }

    private func reconcileQueueIfNeeded(reason: String, preferredCurrentSongId: String? = nil) {
        let diagnostics = queueState.queueDriftDiagnostics
        guard diagnostics.isStale else { return }
        let beforePoolCount = queueState.songCount
        let beforeQueueCount = queueState.queueOrder.count
        let beforeCurrent = queueState.currentSongId ?? "nil"

        queueDriftTelemetry.detections += 1
        queueDriftTelemetry.detectionsByTrigger[reason, default: 0] += 1
        for driftReason in diagnostics.reasons {
            queueDriftTelemetry.detectionsByReason[driftReason, default: 0] += 1
        }

        queueState = queueState.reconcilingQueue(preferredCurrentSongId: preferredCurrentSongId)

        let afterPoolCount = queueState.songCount
        let afterQueueCount = queueState.queueOrder.count
        let afterCurrent = queueState.currentSongId ?? "nil"
        let repaired = !queueState.isQueueStale
        queueDriftTelemetry.reconciliations += 1
        if !repaired {
            queueDriftTelemetry.unrepairedDetections += 1
        }

        let event = QueueDriftEvent(
            timestamp: Date(),
            trigger: reason,
            reasons: diagnostics.reasons.sorted { $0.rawValue < $1.rawValue },
            poolCount: diagnostics.poolCount,
            queueCount: diagnostics.queueCount,
            duplicateCount: diagnostics.duplicateQueueIDs.count,
            missingFromQueueCount: diagnostics.missingFromQueue.count,
            missingFromPoolCount: diagnostics.missingFromPool.count,
            currentSongId: queueState.currentSongId,
            preferredCurrentSongId: preferredCurrentSongId,
            repaired: repaired
        )
        queueDriftTelemetry.recentEvents.insert(event, at: 0)
        if queueDriftTelemetry.recentEvents.count > 20 {
            queueDriftTelemetry.recentEvents.removeLast(queueDriftTelemetry.recentEvents.count - 20)
        }

        print(
            "🛠️ Queue reconciliation [\(reason)] pool \(beforePoolCount)->\(afterPoolCount), " +
            "queue \(beforeQueueCount)->\(afterQueueCount), current \(beforeCurrent)->\(afterCurrent), " +
            "reasons=\(event.reasons.map(\.rawValue)), duplicateIDs=\(diagnostics.duplicateQueueIDs.count), " +
            "missingFromQueue=\(diagnostics.missingFromQueue.count), missingFromPool=\(diagnostics.missingFromPool.count), " +
            "repaired=\(repaired)"
        )
    }

    // MARK: - Algorithm Change

    /// Called when shuffle algorithm changes. Views should call this via onChange(of: appSettings.shuffleAlgorithm).
    func reshuffleWithNewAlgorithm(_ algorithm: ShuffleAlgorithm) async {
        guard !queueState.isEmpty else { return }
        reconcileQueueIfNeeded(reason: "reshuffle-start", preferredCurrentSongId: playbackState.currentSongId)

        // If not actively playing, invalidate the queue so next play() rebuilds with the new algorithm
        guard playbackState.isActive else {
            print("🎲 Algorithm changed to \(algorithm.displayName) while not active, invalidating queue")
            queueState = queueState.invalidatingQueue(using: algorithm)
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
            let policy: QueueApplyPolicy = playbackState.isPlaying ? .forcePlaying : .forcePaused
            try await musicService.replaceQueue(
                queue: queueState.upcomingSongs,
                startAtSongId: currentSong.id,
                policy: policy
            )
            print("🎲 replaceQueue succeeded")
        } catch {
            print("🎲 replaceQueue FAILED: \(error)")
        }
    }

    // MARK: - Song Management

    func addSong(_ song: Song) async throws {
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
            do {
                try await musicService.insertIntoQueue(songs: [song])
                print("🎵 Successfully inserted \(song.title) into MusicKit queue")
            } catch {
                // Rollback completely so pool/queue invariants remain intact.
                queueState = queueState.removingSong(id: song.id)
                print("⚠️ Rolled back \(song.title) from pool+queue after insert failure: \(error)")
            }
        } else {
            print("➕ addSong: playback not active or no queue yet, song only added to pool")
        }
        if playbackState.isActive {
            reconcileQueueIfNeeded(reason: "add-song", preferredCurrentSongId: playbackState.currentSongId)
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
    func addSongsWithQueueRebuild(_ newSongs: [Song], algorithm: ShuffleAlgorithm? = nil) async throws {
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

            let effectiveAlgorithm = algorithm ?? queueState.algorithm

            // Reshuffle upcoming songs (this excludes played songs and current song)
            queueState = queueState.reshuffledUpcoming(with: effectiveAlgorithm)

            print("🎵 Reshuffling with \(addedCount) new songs interleaved")

            do {
                let policy: QueueApplyPolicy = playbackState.isPlaying ? .forcePlaying : .forcePaused
                try await musicService.replaceQueue(
                    queue: queueState.upcomingSongs,
                    startAtSongId: currentSong.id,
                    policy: policy
                )
                print("🎵 Successfully reshuffled queue with \(queueState.queueOrder.count) total songs")
            } catch {
                print("🎵 Failed to reshuffle queue: \(error)")
            }
        }
        if playbackState.isActive {
            reconcileQueueIfNeeded(reason: "add-songs-with-rebuild", preferredCurrentSongId: playbackState.currentSongId)
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
            // Removing upcoming song - rebuild queue without it while preserving current entry.
            do {
                let policy: QueueApplyPolicy = playbackState.isPlaying ? .forcePlaying : .forcePaused
                try await musicService.replaceQueue(
                    queue: queueState.upcomingSongs,
                    startAtSongId: currentSong.id,
                    policy: policy
                )
                print("🎵 Removed song \(id) from MusicKit queue")
            } catch {
                print("🎵 Failed to remove song from MusicKit queue: \(error)")
            }
        }

        reconcileQueueIfNeeded(reason: "remove-song", preferredCurrentSongId: playbackState.currentSongId)
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

        let effectiveAlgorithm = algorithm ?? queueState.algorithm

        print("🎲 prepareQueue: songPool has \(queueState.songCount) songs")

        // Shuffle the queue
        queueState = queueState.shuffled(with: effectiveAlgorithm)
        print("🎲 Prepared queue with algorithm: \(effectiveAlgorithm.displayName)")
        print("🎲 prepareQueue: queueOrder now has \(queueState.queueOrder.count) songs")

        try await musicService.setQueue(songs: queueState.queueOrder)
    }

    // MARK: - Playback Control

    func play(algorithm: ShuffleAlgorithm? = nil) async throws {
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
            try await prepareQueue(algorithm: algorithm)
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

    func togglePlayback(algorithm: ShuffleAlgorithm? = nil) async throws {
        switch playbackState {
        case .empty, .stopped:
            try await play(algorithm: algorithm)
        case .playing:
            await pause()
        case .paused:
            // If we have songs but no queue (e.g., after clear + re-add), build queue first
            if !queueState.isEmpty && !queueState.hasQueue {
                print("▶️ togglePlayback: paused but no queue, calling play() to rebuild")
                try await play(algorithm: algorithm)
            } else {
                try await musicService.play()
            }
        case .loading:
            // Do nothing while loading
            break
        case .error:
            // Try to play again
            try await play(algorithm: algorithm)
        }
    }

    // MARK: - Queue Restoration

    /// Restores session state from persistence without auto-starting playback.
    /// - Parameters:
    ///   - queueOrder: Array of song IDs representing the queue order
    ///   - currentSongId: The ID of the song that was playing
    ///   - playedIds: Set of song IDs that have been played
    ///   - playbackPosition: The position in seconds to seek to
    /// - Returns: True if restoration was successful, false if a fresh shuffle is needed
    func restoreSession(
        queueOrder: [String],
        currentSongId: String?,
        playedIds: Set<String>,
        playbackPosition: TimeInterval
    ) async -> Bool {
        print("🔄 restoreSession called: songs=\(queueState.songCount), queueOrder=\(queueOrder.count), currentSongId=\(currentSongId ?? "nil")")
        pendingRestoreSeek = nil

        guard !queueState.isEmpty else {
            print("🔄 restoreSession: No songs in pool, returning false")
            return false
        }

        // Attempt to restore from persisted state
        guard let restoredState = queueState.restored(
            queueOrder: queueOrder,
            currentSongId: currentSongId,
            playedIds: playedIds
        ) else {
            print("🔄 restoreSession: Failed to restore state, returning false")
            return false
        }

        // Apply restored state
        queueState = restoredState
        lastObservedSongId = queueState.currentSongId
        print("🔄 restoreSession: Restored state with \(queueState.queueOrder.count) songs, current=\(queueState.currentSong?.title ?? "none")")

        // Suppress history updates during the restore sequence
        suppressHistoryUpdates = true
        defer { suppressHistoryUpdates = false }

        // Restore queue and position without auto-starting playback.
        do {
            print("🔄 restoreSession: Restoring queue with \(queueState.queueOrder.count) songs")
            try await musicService.replaceQueue(
                queue: queueState.queueOrder,
                startAtSongId: queueState.currentSongId,
                policy: .forcePaused
            )

            // Seek to saved position (best-effort, no autoplay probe).
            let clampedPosition = max(0, playbackPosition)
            if clampedPosition > 0 {
                print("🔄 restoreSession: Seeking to position \(clampedPosition)")
                musicService.seek(to: clampedPosition)
                if let currentSongId = queueState.currentSongId {
                    pendingRestoreSeek = (songId: currentSongId, position: clampedPosition)
                }
            }

            print("🔄 restoreSession: Applying paused state without forcing extra transport pause")
            if let current = queueState.currentSong {
                // Preserve richer transport metadata (artwork/title updates) when already available.
                let hydratedCurrent: Song
                if let observedCurrent = playbackState.currentSong, observedCurrent.id == current.id {
                    hydratedCurrent = observedCurrent
                } else {
                    hydratedCurrent = current
                }
                playbackState = .paused(hydratedCurrent)
            } else {
                playbackState = .stopped
            }

            print("🔄 restoreSession: Success!")
            return true
        } catch {
            print("🔄 restoreSession: Failed to set queue: \(error)")
            return false
        }
    }

    /// Backward-compat wrapper.
    func restoreQueue(
        queueOrder: [String],
        currentSongId: String?,
        playedIds: Set<String>,
        playbackPosition: TimeInterval
    ) async -> Bool {
        await restoreSession(
            queueOrder: queueOrder,
            currentSongId: currentSongId,
            playedIds: playedIds,
            playbackPosition: playbackPosition
        )
    }
}
