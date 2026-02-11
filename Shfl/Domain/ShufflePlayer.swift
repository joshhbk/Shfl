import Foundation

@Observable
@MainActor
final class ShufflePlayer {
    static let maxSongs = 120

    @ObservationIgnored private let musicService: MusicService
    @ObservationIgnored private let playbackObserver: PlaybackStateObserver

    /// Single source of truth for queue state
    private(set) var queueState: QueueState = .empty

    /// Current playback state from MusicKit
    private(set) var playbackState: PlaybackState = .empty

    /// Diagnostics for queue drift detection and reconciliation.
    private(set) var queueDriftTelemetry = QueueDriftTelemetry()

    /// Non-blocking operation notice for queue/transport sync failures.
    private(set) var operationNotice: String?

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

    /// Debug: Number of entries in the MusicKit transport queue
    var transportQueueEntryCount: Int { musicService.transportQueueEntryCount }

    /// Debug: ID of the song currently selected in the MusicKit transport
    var transportCurrentSongId: String? { musicService.currentSongId }

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
        self.playbackObserver = PlaybackStateObserver(musicService: musicService)
        startObserving()
    }

    deinit {
        // PlaybackStateObserver cancels its own task in its deinit.
    }

    // MARK: - Playback State Observation

    private func startObserving() {
        playbackObserver.startObserving(
            queueState: { [weak self] in self?.queueState ?? .empty },
            onResolution: { [weak self] resolution in
                self?.applyResolution(resolution)
            }
        )
    }

    private func applyResolution(_ resolution: PlaybackStateResolution) {
        if resolution.shouldUpdateCurrentSong, let songId = resolution.resolvedSongId {
            queueState = queueState.settingCurrentSong(id: songId)
        }
        if let playedId = resolution.songIdToMarkPlayed {
            queueState = queueState.markingAsPlayed(id: playedId)
        }
        if resolution.shouldClearHistory {
            queueState = queueState.clearingPlayedHistory()
        }
        if resolution.shouldReconcile {
            reconcileQueueIfNeeded(reason: "playback-state-change", preferredCurrentSongId: resolution.resolvedSongId)
        }
        if let seek = resolution.pendingSeekConsumed {
            musicService.seek(to: seek.position)
        }
        playbackState = resolution.resolvedState
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

        let transportCount = musicService.transportQueueEntryCount
        let transportCurrentId = musicService.currentSongId
        let transportParityMismatch = transportCount != queueState.queueOrder.count
            || transportCurrentId != queueState.currentSongId

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
            repaired: repaired,
            transportEntryCount: transportCount,
            transportCurrentSongId: transportCurrentId,
            transportParityMismatch: transportParityMismatch
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

    func clearOperationNotice() {
        operationNotice = nil
    }

    private func reportTransportFailure(action: String, error: Error) -> String {
        let message = Self.isLikelyOfflineError(error)
            ? "\(action) while offline. Reconnect and try again."
            : "\(action). Please try again."
        operationNotice = message
        print("⚠️ \(action): \(error)")
        return message
    }

    private static func isLikelyOfflineError(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else { return false }

        return [
            NSURLErrorNotConnectedToInternet,
            NSURLErrorNetworkConnectionLost,
            NSURLErrorTimedOut,
            NSURLErrorCannotFindHost,
            NSURLErrorCannotConnectToHost,
            NSURLErrorInternationalRoamingOff,
            NSURLErrorDataNotAllowed,
            NSURLErrorCallIsActive
        ].contains(nsError.code)
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

        let stateBeforeReshuffle = queueState

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
            queueState = stateBeforeReshuffle
            _ = reportTransportFailure(action: "Couldn't reshuffle the active queue", error: error)
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
                let message = reportTransportFailure(action: "Couldn't add the song to the active queue", error: error)
                throw ShufflePlayerError.playbackFailed(message)
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
        let stateBeforeQueueRebuild = queueState
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
                queueState = stateBeforeQueueRebuild
                let message = reportTransportFailure(action: "Couldn't sync newly added songs to the active queue", error: error)
                print("🎵 Failed to reshuffle queue: \(error)")
                throw ShufflePlayerError.playbackFailed(message)
            }
        }
        if playbackState.isActive {
            reconcileQueueIfNeeded(reason: "add-songs-with-rebuild", preferredCurrentSongId: playbackState.currentSongId)
        }
        print("🔍 addSongsWithQueueRebuild: Complete")
    }

    func removeSong(id: String) async {
        let previousState = queueState
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
                queueState = previousState
                _ = reportTransportFailure(action: "Couldn't remove the currently playing song", error: error)
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
                queueState = previousState
                _ = reportTransportFailure(action: "Couldn't remove the song from the active queue", error: error)
                print("🎵 Failed to remove song from MusicKit queue: \(error)")
            }
        }

        reconcileQueueIfNeeded(reason: "remove-song", preferredCurrentSongId: playbackState.currentSongId)
    }

    func removeAllSongs() async {
        print("🗑️ removeAllSongs() called: had \(queueState.songCount) songs, queueOrder had \(queueState.queueOrder.count)")
        queueState = queueState.cleared()
        playbackObserver.clearLastObservedSongId()

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
        playbackObserver.clearLastObservedSongId()

        print("▶️ play() preparing queue...")
        try await prepareQueue(algorithm: algorithm)
        // Emit loading with the actual first song from shuffled queue
        if let firstSong = queueState.currentSong {
            playbackState = .loading(firstSong)
        }
        print("▶️ play() queue prepared, order has \(queueState.queueOrder.count) songs")

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
        playbackObserver.clearPendingRestoreSeek()

        playbackObserver.beginSuppressingHistory()
        defer { playbackObserver.endSuppressingHistory() }

        let restorer = SessionRestorer(musicService: musicService)
        guard let result = await restorer.restore(
            queueState: queueState,
            currentPlaybackState: playbackState,
            queueOrder: queueOrder,
            currentSongId: currentSongId,
            playedIds: playedIds,
            playbackPosition: playbackPosition
        ) else {
            return false
        }

        queueState = result.restoredQueueState
        playbackState = result.restoredPlaybackState
        playbackObserver.setLastObservedSongId(result.lastObservedSongId)
        if let seek = result.pendingRestoreSeek {
            playbackObserver.setPendingRestoreSeek(songId: seek.songId, position: seek.position)
        }
        return true
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
