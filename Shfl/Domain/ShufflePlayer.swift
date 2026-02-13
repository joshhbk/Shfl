import Foundation

@Observable
@MainActor
final class ShufflePlayer {
    static let maxSongs = 120

    @ObservationIgnored private let musicService: MusicService
    @ObservationIgnored private let playbackObserver: PlaybackStateObserver
    @ObservationIgnored private var transportCommandQueue: Task<Void, Error>?
    @ObservationIgnored private var transportCommandQueueHead = 0
    @ObservationIgnored private var cachedTransportSnapshot = TransportSnapshot(entryCount: 0, currentSongId: nil)

    /// Single source of truth for queue state
    private(set) var queueState: QueueState = .empty

    /// Current playback state from MusicKit
    private(set) var playbackState: PlaybackState = .empty

    /// Monotonic revision used to gate stale transport commands.
    private(set) var queueRevision: Int = 0

    /// Whether playback should rebuild transport queue before attempting play.
    private(set) var queueNeedsBuild = true

    /// Diagnostics for queue drift detection and reconciliation.
    private(set) var queueDriftTelemetry = QueueDriftTelemetry()

    /// Rolling operation journal for queue diagnostics.
    private(set) var queueOperationJournal = QueueOperationJournal()

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

    /// Debug: recent queue operations (most recent first).
    var recentQueueOperations: [QueueOperationRecord] { queueOperationJournal.records }

    /// Debug: latest invariant check over domain + transport queue state.
    var queueInvariantCheck: QueueInvariantCheck { evaluateQueueInvariants() }

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
        recordOperation("player-init")
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
        if let reduction = try? reduce(.playbackResolution(resolution)) {
            applyReduction(reduction)
        }
        if let seek = resolution.pendingSeekConsumed {
            musicService.seek(to: seek.position)
        }
        recordOperation(
            "playback-resolution",
            detail: "state=\(playbackStateLabel(resolution.resolvedState)), song=\(resolution.resolvedSongId ?? "nil")"
        )
    }

    func clearOperationNotice() {
        operationNotice = nil
        recordOperation("clear-operation-notice")
    }

    /// Debug-only escape hatch to return queue and diagnostics to a clean baseline.
    func hardResetQueueForDebug() async {
        await removeAllSongs()
        queueDriftTelemetry = QueueDriftTelemetry()
        queueOperationJournal = QueueOperationJournal()
        operationNotice = nil
        playbackObserver.clearLastObservedSongId()
        playbackObserver.clearPendingRestoreSeek()
        recordOperation("hard-reset-queue")
    }

    private func reportTransportFailure(action: String, error: Error) -> String {
        let message = Self.isLikelyOfflineError(error)
            ? "\(action) while offline. Reconnect and try again."
            : "\(action). Please try again."
        operationNotice = message
        print("⚠️ \(action): \(error)")
        recordOperation("transport-failure", detail: "\(action): \(error.localizedDescription)")
        return message
    }

    private enum TransportCommandExecutionError: Error {
        case staleRevision(commandRevision: Int, queueRevision: Int)
    }

    private struct TransportSnapshot {
        let entryCount: Int
        let currentSongId: String?
    }

    @discardableResult
    private func handleStaleTransportCommand(_ error: Error, source: String) -> Bool {
        guard case let TransportCommandExecutionError.staleRevision(commandRevision, queueRevision) = error else {
            return false
        }

        queueNeedsBuild = true
        operationNotice = "Queue changed while syncing. Rebuilding queue."
        recordOperation(
            "transport-command-stale",
            detail: "source=\(source), commandRevision=\(commandRevision), queueRevision=\(queueRevision)"
        )
        return true
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

    private var engineState: QueueEngineState {
        QueueEngineState(
            queueState: queueState,
            playbackState: playbackState,
            revision: queueRevision,
            queueNeedsBuild: queueNeedsBuild
        )
    }

    private func applyReduction(_ reduction: QueueEngineReduction) {
        queueState = reduction.nextState.queueState
        playbackState = reduction.nextState.playbackState
        queueRevision = reduction.nextState.revision
        queueNeedsBuild = reduction.nextState.queueNeedsBuild
        enforceDomainInvariants(context: "reduction")
    }

    private func enforceDomainInvariants(context: String) {
        let queueIds = queueState.queueOrder.map(\.id)
        let queueIdSet = Set(queueIds)
        let poolIdSet = Set(queueState.songPool.map(\.id))
        let hasValidCurrent = !queueState.hasQueue || queueState.currentSong != nil
        let queueMembershipIsValid: Bool
        if queueState.hasQueue {
            if queueNeedsBuild {
                // Degraded mode: transport sync failed or queue was invalidated; rebuild is pending.
                queueMembershipIsValid = true
            } else {
                queueMembershipIsValid = queueIds.count == queueIdSet.count && queueIdSet == poolIdSet
            }
        } else {
            // It's valid to have songs in the pool with no queue yet; queue is lazily built on play.
            queueMembershipIsValid = queueState.isEmpty || queueNeedsBuild || !playbackState.isActive
        }
        let isHealthy = queueMembershipIsValid && hasValidCurrent

        guard !queueState.isEmpty else { return }
        guard !isHealthy else { return }

#if DEBUG
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            assertionFailure("Queue invariant violation [\(context)]")
        } else {
            operationNotice = "Queue sync issue detected. Rebuilding queue."
        }
#else
        operationNotice = "Queue sync issue detected. Rebuilding queue."
#endif
        recordOperation(
            "invariant-violation",
            detail: "context=\(context), pool=\(queueState.songPool.count), queue=\(queueState.queueOrder.count)"
        )
    }

    private func executeTransportCommand(_ command: TransportCommand) async throws {
        guard command.revision == queueRevision else {
            throw TransportCommandExecutionError.staleRevision(
                commandRevision: command.revision,
                queueRevision: queueRevision
            )
        }

        switch command {
        case .setQueue(let songs, _):
            try await musicService.setQueue(songs: songs)
        case .insertIntoQueue(let songs, _):
            try await musicService.insertIntoQueue(songs: songs)
        case .replaceQueue(let queue, let startAtSongId, let policy, _):
            try await musicService.replaceQueue(queue: queue, startAtSongId: startAtSongId, policy: policy)
        case .play:
            try await musicService.play()
        case .pause:
            await musicService.pause()
        case .skipToNext:
            try await musicService.skipToNext()
        case .skipToPrevious:
            try await musicService.skipToPrevious()
        case .restartOrSkipToPrevious:
            try await musicService.restartOrSkipToPrevious()
        }
    }

    private func enqueueTransportCommands(_ commands: [TransportCommand]) async throws {
        guard !commands.isEmpty else { return }

        let previous = transportCommandQueue
        transportCommandQueueHead += 1
        let head = transportCommandQueueHead

        let task = Task<Void, Error> { @MainActor [weak self] in
            if let previous {
                try await previous.value
            }
            guard let self else { return }
            for command in commands {
                try await self.executeTransportCommand(command)
            }
        }

        transportCommandQueue = task
        defer {
            if transportCommandQueueHead == head {
                transportCommandQueue = nil
            }
        }

        try await task.value
    }

    private func reduce(_ intent: QueueIntent) throws -> QueueEngineReduction {
        try QueueEngineReducer.reduce(state: engineState, intent: intent)
    }

    private func playbackStateLabel(_ state: PlaybackState) -> String {
        switch state {
        case .empty:
            return "empty"
        case .stopped:
            return "stopped"
        case .loading:
            return "loading"
        case .playing:
            return "playing"
        case .paused:
            return "paused"
        case .error(let error):
            return "error(\(error.localizedDescription))"
        }
    }

    private func domainInvariantReasons(
        poolIds: [String],
        queueIds: [String],
        poolIdSet: Set<String>,
        queueIdSet: Set<String>,
        queueParityExpected: Bool,
        playbackCurrentSongId: String?
    ) -> [String] {
        var reasons: [String] = []

        if !queueState.hasQueue || queueIds.count == queueIdSet.count {
            // no-op
        } else {
            reasons.append("duplicate-queue-ids")
        }

        if !queueParityExpected || poolIdSet == queueIdSet {
            // no-op
        } else {
            reasons.append("pool-queue-membership-mismatch")
        }

        if queueParityExpected && queueIds.count != poolIds.count {
            reasons.append("pool-queue-count-mismatch")
        }

        if queueState.hasQueue && queueState.currentSong == nil {
            reasons.append("current-index-out-of-bounds")
        }

        if let playbackCurrentSongId,
           !poolIdSet.contains(playbackCurrentSongId) {
            reasons.append("playback-song-not-in-pool")
        }

        return reasons
    }

    private func evaluateDomainInvariants() -> (isHealthy: Bool, reasons: [String]) {
        let poolIds = queueState.songPool.map(\.id)
        let queueIds = queueState.queueOrder.map(\.id)
        let poolIdSet = Set(poolIds)
        let queueIdSet = Set(queueIds)
        let queueParityExpected = !queueNeedsBuild && (queueState.hasQueue || playbackState.isActive)
        let reasons = domainInvariantReasons(
            poolIds: poolIds,
            queueIds: queueIds,
            poolIdSet: poolIdSet,
            queueIdSet: queueIdSet,
            queueParityExpected: queueParityExpected,
            playbackCurrentSongId: playbackState.currentSongId
        )
        return (isHealthy: reasons.isEmpty, reasons: reasons)
    }

    private func refreshTransportSnapshot() -> TransportSnapshot {
        let snapshot = TransportSnapshot(
            entryCount: musicService.transportQueueEntryCount,
            currentSongId: musicService.currentSongId
        )
        cachedTransportSnapshot = snapshot
        return snapshot
    }

    private func evaluateQueueInvariants() -> QueueInvariantCheck {
        let poolIds = queueState.songPool.map(\.id)
        let queueIds = queueState.queueOrder.map(\.id)
        let poolIdSet = Set(poolIds)
        let queueIdSet = Set(queueIds)
        let queueParityExpected = !queueNeedsBuild && (queueState.hasQueue || playbackState.isActive)
        let playbackCurrentSongId = playbackState.currentSongId

        let queueHasUniqueIDs = !queueState.hasQueue || queueIds.count == queueIdSet.count
        let poolAndQueueMembershipMatch = !queueParityExpected || poolIdSet == queueIdSet
        let transportSnapshot = refreshTransportSnapshot()
        let transportEntryCount = transportSnapshot.entryCount
        let transportCurrentSongId = transportSnapshot.currentSongId
        let transportEntryCountMatchesQueue = !queueParityExpected || transportEntryCount == queueIds.count
        let transportCurrentMatchesDomain =
            !queueParityExpected ||
            transportCurrentSongId == queueState.currentSongId ||
            playbackCurrentSongId == queueState.currentSongId

        var reasons = domainInvariantReasons(
            poolIds: poolIds,
            queueIds: queueIds,
            poolIdSet: poolIdSet,
            queueIdSet: queueIdSet,
            queueParityExpected: queueParityExpected,
            playbackCurrentSongId: playbackCurrentSongId
        )
        if !transportEntryCountMatchesQueue {
            reasons.append("transport-entry-count-mismatch")
        }
        if !transportCurrentMatchesDomain {
            reasons.append("transport-current-song-mismatch")
        }

        return QueueInvariantCheck(
            isHealthy: reasons.isEmpty,
            reasons: reasons,
            poolCount: queueState.songPool.count,
            queueCount: queueState.queueOrder.count,
            playedCount: queueState.playedIds.count,
            currentIndex: queueState.currentIndex,
            domainCurrentSongId: queueState.currentSongId,
            playbackCurrentSongId: playbackCurrentSongId,
            transportEntryCount: transportEntryCount,
            transportCurrentSongId: transportCurrentSongId,
            queueHasUniqueIDs: queueHasUniqueIDs,
            poolAndQueueMembershipMatch: poolAndQueueMembershipMatch,
            transportEntryCountMatchesQueue: transportEntryCountMatchesQueue,
            transportCurrentMatchesDomain: transportCurrentMatchesDomain
        )
    }

    private func recordOperation(_ operation: String, detail: String? = nil) {
        let invariant = evaluateDomainInvariants()
        let transport = cachedTransportSnapshot
        let record = QueueOperationRecord(
            id: UUID(),
            timestamp: Date(),
            operation: operation,
            detail: detail,
            playbackState: playbackStateLabel(playbackState),
            poolCount: queueState.songPool.count,
            queueCount: queueState.queueOrder.count,
            currentSongId: queueState.currentSongId,
            transportEntryCount: transport.entryCount,
            transportCurrentSongId: transport.currentSongId,
            invariantHealthy: invariant.isHealthy,
            invariantReasons: invariant.reasons
        )
        queueOperationJournal.append(record)
    }

    func exportQueueDiagnosticsSnapshot(trigger: String = "manual-export", detail: String? = nil) -> String {
        let invariant = evaluateQueueInvariants()
        recordOperation("snapshot-export", detail: [trigger, detail].compactMap { $0 }.joined(separator: " | "))
        let snapshot = QueueDiagnosticsSnapshot(
            exportedAt: Date(),
            trigger: trigger,
            detail: detail,
            playbackState: playbackStateLabel(playbackState),
            poolSongIds: queueState.songPool.map(\.id),
            queueSongIds: queueState.queueOrder.map(\.id),
            playedSongIds: queueState.playedIds.sorted(),
            currentIndex: queueState.currentIndex,
            currentSongId: queueState.currentSongId,
            transportEntryCount: invariant.transportEntryCount,
            transportCurrentSongId: invariant.transportCurrentSongId,
            invariantCheck: invariant,
            driftTelemetry: QueueDriftTelemetrySnapshot(queueDriftTelemetry),
            operationJournal: queueOperationJournal.records
        )

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(snapshot)
            return String(decoding: data, as: UTF8.self)
        } catch {
            recordOperation("snapshot-export-failed", detail: error.localizedDescription)
            return "{\"error\":\"snapshot-export-failed\"}"
        }
    }

    // MARK: - Algorithm Change

    /// Called when shuffle algorithm changes. Views should call this via onChange(of: appSettings.shuffleAlgorithm).
    func reshuffleWithNewAlgorithm(_ algorithm: ShuffleAlgorithm) async {
        do {
            let reduction = try reduce(.reshuffleAlgorithm(algorithm))
            guard !reduction.wasNoOp else {
                recordOperation("reshuffle-algorithm-skip", detail: "no-op")
                return
            }

            let previousState = engineState
            applyReduction(reduction)
            do {
                try await enqueueTransportCommands(reduction.transportCommands)
                if playbackState.isActive {
                    recordOperation("reshuffle-algorithm-success", detail: algorithm.rawValue)
                } else {
                    recordOperation("reshuffle-algorithm-invalidated", detail: algorithm.rawValue)
                }
            } catch {
                if handleStaleTransportCommand(error, source: "reshuffle-algorithm") {
                    return
                }
                queueState = previousState.queueState
                playbackState = previousState.playbackState
                queueRevision = previousState.revision
                queueNeedsBuild = previousState.queueNeedsBuild
                _ = reportTransportFailure(action: "Couldn't reshuffle the active queue", error: error)
                recordOperation("reshuffle-algorithm-failed", detail: error.localizedDescription)
            }
        } catch {
            recordOperation("reshuffle-algorithm-failed", detail: error.localizedDescription)
        }
    }

    // MARK: - Song Management

    func addSong(_ song: Song) async throws {
        do {
            let reduction = try reduce(.addSong(song))
            guard !reduction.wasNoOp else {
                recordOperation("add-song-skip", detail: "duplicate id=\(song.id)")
                return
            }

            let previousState = engineState
            applyReduction(reduction)
            do {
                try await enqueueTransportCommands(reduction.transportCommands)
                recordOperation("add-song-success", detail: "id=\(song.id)")
            } catch {
                if handleStaleTransportCommand(error, source: "add-song") {
                    recordOperation("add-song-deferred-rebuild", detail: "id=\(song.id)")
                    return
                }
                // Keep the newly added song in the pool, but roll back queue ordering until next rebuild.
                queueState = QueueState(
                    songPool: queueState.songPool,
                    queueOrder: previousState.queueState.queueOrder,
                    playedIds: previousState.queueState.playedIds,
                    currentIndex: previousState.queueState.currentIndex,
                    algorithm: previousState.queueState.algorithm
                )
                playbackState = previousState.playbackState
                queueNeedsBuild = true
                let message = reportTransportFailure(action: "Couldn't add the song to the active queue", error: error)
                recordOperation("add-song-failed", detail: "transport-replace-failed id=\(song.id)")
                throw ShufflePlayerError.playbackFailed(message)
            }
        } catch QueueEngineError.capacityReached {
            recordOperation("add-song-failed", detail: "capacity-reached id=\(song.id)")
            throw ShufflePlayerError.capacityReached
        } catch {
            let message = reportTransportFailure(action: "Couldn't add the song to the active queue", error: error)
            recordOperation("add-song-failed", detail: "unexpected id=\(song.id)")
            throw ShufflePlayerError.playbackFailed(message)
        }
    }

    func addSongs(_ newSongs: [Song]) throws {
        do {
            let reduction = try reduce(.addSongs(newSongs))
            guard !reduction.wasNoOp else { return }
            applyReduction(reduction)
            recordOperation("add-songs-success", detail: "batch=\(newSongs.count)")
        } catch QueueEngineError.capacityReached {
            recordOperation("add-songs-failed", detail: "capacity-reached batch=\(newSongs.count)")
            throw ShufflePlayerError.capacityReached
        } catch {
            recordOperation("add-songs-failed", detail: "unexpected batch=\(newSongs.count)")
            throw ShufflePlayerError.playbackFailed(error.localizedDescription)
        }
    }

    /// Add songs and reshuffle queue if playing (interleaves new songs throughout upcoming queue)
    func addSongsWithQueueRebuild(_ newSongs: [Song], algorithm: ShuffleAlgorithm? = nil) async throws {
        do {
            let reduction = try reduce(.addSongsWithRebuild(newSongs, algorithm: algorithm))
            guard !reduction.wasNoOp else { return }

            let previousState = engineState
            applyReduction(reduction)
            do {
                try await enqueueTransportCommands(reduction.transportCommands)
                recordOperation("add-songs-rebuild-success", detail: "batch=\(newSongs.count)")
            } catch {
                if handleStaleTransportCommand(error, source: "add-songs-rebuild") {
                    recordOperation("add-songs-rebuild-deferred", detail: "batch=\(newSongs.count)")
                    return
                }
                // Preserve newly added songs in pool and defer queue rebuild to next play.
                queueState = QueueState(
                    songPool: queueState.songPool,
                    queueOrder: previousState.queueState.queueOrder,
                    playedIds: previousState.queueState.playedIds,
                    currentIndex: previousState.queueState.currentIndex,
                    algorithm: previousState.queueState.algorithm
                )
                playbackState = previousState.playbackState
                queueNeedsBuild = true
                let message = reportTransportFailure(action: "Couldn't sync newly added songs to the active queue", error: error)
                recordOperation("add-songs-rebuild-failed", detail: "transport-replace-failed")
                throw ShufflePlayerError.playbackFailed(message)
            }
        } catch QueueEngineError.capacityReached {
            recordOperation("add-songs-rebuild-failed", detail: "capacity-reached batch=\(newSongs.count)")
            throw ShufflePlayerError.capacityReached
        } catch {
            let message = reportTransportFailure(action: "Couldn't sync newly added songs to the active queue", error: error)
            recordOperation("add-songs-rebuild-failed", detail: "unexpected")
            throw ShufflePlayerError.playbackFailed(message)
        }
    }

    func removeSong(id: String) async {
        do {
            let reduction = try reduce(.removeSong(id: id))
            guard !reduction.wasNoOp else { return }

            let previousState = engineState
            applyReduction(reduction)
            do {
                try await enqueueTransportCommands(reduction.transportCommands)
                recordOperation("remove-song-success", detail: "id=\(id)")
            } catch {
                if handleStaleTransportCommand(error, source: "remove-song") {
                    return
                }
                queueState = previousState.queueState
                playbackState = previousState.playbackState
                queueRevision = previousState.revision
                queueNeedsBuild = previousState.queueNeedsBuild
                _ = reportTransportFailure(action: "Couldn't remove the song from the active queue", error: error)
                recordOperation("remove-song-failed", detail: "id=\(id)")
            }
        } catch {
            _ = reportTransportFailure(action: "Couldn't remove the song from the active queue", error: error)
            recordOperation("remove-song-failed", detail: "id=\(id), unexpected")
        }
    }

    func removeAllSongs() async {
        do {
            let reduction = try reduce(.removeAllSongs)
            guard !reduction.wasNoOp else { return }

            applyReduction(reduction)
            playbackObserver.clearLastObservedSongId()
            do {
                try await enqueueTransportCommands(reduction.transportCommands)
            } catch {
                if handleStaleTransportCommand(error, source: "remove-all-songs") {
                    recordOperation("remove-all-songs-deferred")
                    return
                }
                _ = reportTransportFailure(action: "Couldn't clear the active queue", error: error)
            }
            recordOperation("remove-all-songs")
        } catch {
            _ = reportTransportFailure(action: "Couldn't clear the active queue", error: error)
            recordOperation("remove-all-songs-failed", detail: error.localizedDescription)
        }
    }

    func containsSong(id: String) -> Bool {
        queueState.containsSong(id: id)
    }

    // MARK: - Queue Preparation

    func prepareQueue(algorithm: ShuffleAlgorithm? = nil) async throws {
        let reduction = try reduce(.prepareQueue(algorithm: algorithm))
        guard !reduction.wasNoOp else {
            recordOperation("prepare-queue-skip", detail: "empty-pool")
            return
        }

        let previousState = engineState
        applyReduction(reduction)
        do {
            try await enqueueTransportCommands(reduction.transportCommands)
            recordOperation("prepare-queue-success", detail: queueState.algorithm.rawValue)
        } catch {
            if handleStaleTransportCommand(error, source: "prepare-queue") {
                throw ShufflePlayerError.playbackFailed("Queue changed while syncing. Try again.")
            }
            queueState = previousState.queueState
            playbackState = previousState.playbackState
            queueRevision = previousState.revision
            queueNeedsBuild = previousState.queueNeedsBuild
            throw error
        }
    }

    // MARK: - Playback Control

    func play(algorithm: ShuffleAlgorithm? = nil) async throws {
        let reduction = try reduce(.play(algorithm: algorithm))
        guard !reduction.wasNoOp else {
            recordOperation("play-skip", detail: "empty-pool")
            return
        }

        let previousState = engineState
        applyReduction(reduction)
        playbackObserver.clearLastObservedSongId()
        do {
            try await enqueueTransportCommands(reduction.transportCommands)
            recordOperation("play-success")
        } catch {
            if handleStaleTransportCommand(error, source: "play") {
                throw ShufflePlayerError.playbackFailed("Queue changed while syncing. Tap play again.")
            }
            queueState = previousState.queueState
            playbackState = previousState.playbackState
            queueRevision = previousState.revision
            queueNeedsBuild = previousState.queueNeedsBuild
            throw error
        }
    }

    func pause() async {
        guard let reduction = try? reduce(.pause) else { return }
        applyReduction(reduction)
        do {
            try await enqueueTransportCommands(reduction.transportCommands)
        } catch {
            if handleStaleTransportCommand(error, source: "pause") {
                return
            }
            _ = reportTransportFailure(action: "Couldn't pause playback", error: error)
        }
        recordOperation("pause")
    }

    func skipToNext() async throws {
        let reduction = try reduce(.skipToNext)
        applyReduction(reduction)
        do {
            try await enqueueTransportCommands(reduction.transportCommands)
        } catch {
            if handleStaleTransportCommand(error, source: "skip-next") {
                throw ShufflePlayerError.playbackFailed("Queue changed while syncing. Try skipping again.")
            }
            throw error
        }
        recordOperation("skip-next")
    }

    func skipToPrevious() async throws {
        let reduction = try reduce(.skipToPrevious)
        applyReduction(reduction)
        do {
            try await enqueueTransportCommands(reduction.transportCommands)
        } catch {
            if handleStaleTransportCommand(error, source: "skip-previous") {
                throw ShufflePlayerError.playbackFailed("Queue changed while syncing. Try skipping again.")
            }
            throw error
        }
        recordOperation("skip-previous")
    }

    func restartOrSkipToPrevious() async throws {
        let reduction = try reduce(.restartOrSkipToPrevious)
        applyReduction(reduction)
        do {
            try await enqueueTransportCommands(reduction.transportCommands)
        } catch {
            if handleStaleTransportCommand(error, source: "restart-or-skip-previous") {
                throw ShufflePlayerError.playbackFailed("Queue changed while syncing. Try again.")
            }
            throw error
        }
        recordOperation("restart-or-skip-previous")
    }

    func togglePlayback(algorithm: ShuffleAlgorithm? = nil) async throws {
        let reduction = try reduce(.togglePlayback(algorithm: algorithm))
        guard !reduction.wasNoOp else {
            recordOperation("toggle-playback-skip", detail: "no-op")
            return
        }

        let previousState = engineState
        applyReduction(reduction)
        do {
            try await enqueueTransportCommands(reduction.transportCommands)
            recordOperation("toggle-playback")
        } catch {
            if handleStaleTransportCommand(error, source: "toggle-playback") {
                throw ShufflePlayerError.playbackFailed("Queue changed while syncing. Tap play again.")
            }
            queueState = previousState.queueState
            playbackState = previousState.playbackState
            queueRevision = previousState.revision
            queueNeedsBuild = previousState.queueNeedsBuild
            throw error
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
            recordOperation("restore-session-failed")
            return false
        }

        do {
            let reduction = try reduce(
                .restoreSession(
                    queueState: result.restoredQueueState,
                    playbackState: result.restoredPlaybackState
                )
            )
            applyReduction(reduction)
        } catch {
            recordOperation("restore-session-failed", detail: "reducer=\(error.localizedDescription)")
            return false
        }
        playbackObserver.setLastObservedSongId(result.lastObservedSongId)
        if let seek = result.pendingRestoreSeek {
            playbackObserver.setPendingRestoreSeek(songId: seek.songId, position: seek.position)
        }
        recordOperation("restore-session-success")
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
