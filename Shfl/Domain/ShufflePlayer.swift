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
        recordOperation(
            "transport-failure",
            detail: "\(action): \(error.localizedDescription)",
            refreshTransport: true
        )
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

    private enum RollbackPolicy {
        case none
        case full
        case preservePoolAndDeferQueueBuild
    }

    private enum TransportApplyOutcome {
        case applied
        case stale
    }

    private func restoreEngineState(_ state: QueueEngineState) {
        queueState = state.queueState
        playbackState = state.playbackState
        queueRevision = state.revision
        queueNeedsBuild = state.queueNeedsBuild
    }

    private func rollback(to previousState: QueueEngineState, policy: RollbackPolicy) {
        switch policy {
        case .none:
            return
        case .full:
            restoreEngineState(previousState)
        case .preservePoolAndDeferQueueBuild:
            // Keep newly added songs while reverting queue shape until the next rebuild.
            queueState = QueueState(
                songPool: queueState.songPool,
                queueOrder: previousState.queueState.queueOrder,
                playedIds: previousState.queueState.playedIds,
                currentIndex: previousState.queueState.currentIndex,
                algorithm: previousState.queueState.algorithm
            )
            playbackState = previousState.playbackState
            queueNeedsBuild = true
        }
    }

    private func applyReductionWithTransport(
        _ reduction: QueueEngineReduction,
        source: String,
        rollbackPolicy: RollbackPolicy = .full,
        afterApply: (() -> Void)? = nil
    ) async throws -> TransportApplyOutcome {
        let previousState = engineState
        applyReduction(reduction)
        afterApply?()

        do {
            try await enqueueTransportCommands(reduction.transportCommands)
            _ = refreshTransportSnapshot()
            return .applied
        } catch {
            _ = refreshTransportSnapshot()
            if handleStaleTransportCommand(error, source: source) {
                return .stale
            }
            rollback(to: previousState, policy: rollbackPolicy)
            throw error
        }
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
            guard let self else { return }
            if let previous {
                do {
                    try await previous.value
                } catch {
                    // Earlier callers already handle their own transport errors.
                    // Keep the command queue progressing for newer intents.
                    self.recordOperation(
                        "transport-queue-previous-failed",
                        detail: error.localizedDescription
                    )
                }
            }
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

    private func recordOperation(_ operation: String, detail: String? = nil, refreshTransport: Bool = false) {
        if refreshTransport {
            _ = refreshTransportSnapshot()
        }
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

            do {
                let outcome = try await applyReductionWithTransport(
                    reduction,
                    source: "reshuffle-algorithm",
                    rollbackPolicy: .full
                )
                switch outcome {
                case .applied:
                    if playbackState.isActive {
                        recordOperation("reshuffle-algorithm-success", detail: algorithm.rawValue)
                    } else {
                        recordOperation("reshuffle-algorithm-invalidated", detail: algorithm.rawValue)
                    }
                case .stale:
                    return
                }
            } catch {
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

            do {
                let outcome = try await applyReductionWithTransport(
                    reduction,
                    source: "add-song",
                    rollbackPolicy: .preservePoolAndDeferQueueBuild
                )
                switch outcome {
                case .applied:
                    recordOperation("add-song-success", detail: "id=\(song.id)")
                case .stale:
                    recordOperation("add-song-deferred-rebuild", detail: "id=\(song.id)")
                    return
                }
            } catch {
                let message = reportTransportFailure(action: "Couldn't add the song to the active queue", error: error)
                recordOperation("add-song-failed", detail: "transport-sync-failed id=\(song.id)")
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

            do {
                let outcome = try await applyReductionWithTransport(
                    reduction,
                    source: "add-songs-rebuild",
                    rollbackPolicy: .preservePoolAndDeferQueueBuild
                )
                switch outcome {
                case .applied:
                    recordOperation("add-songs-rebuild-success", detail: "batch=\(newSongs.count)")
                case .stale:
                    recordOperation("add-songs-rebuild-deferred", detail: "batch=\(newSongs.count)")
                    return
                }
            } catch {
                let message = reportTransportFailure(action: "Couldn't sync newly added songs to the active queue", error: error)
                recordOperation("add-songs-rebuild-failed", detail: "transport-sync-failed")
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

            do {
                let outcome = try await applyReductionWithTransport(
                    reduction,
                    source: "remove-song",
                    rollbackPolicy: .full
                )
                guard case .applied = outcome else { return }
                recordOperation("remove-song-success", detail: "id=\(id)")
            } catch {
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

            do {
                let outcome = try await applyReductionWithTransport(
                    reduction,
                    source: "remove-all-songs",
                    rollbackPolicy: .none,
                    afterApply: { self.playbackObserver.clearLastObservedSongId() }
                )
                switch outcome {
                case .applied:
                    recordOperation("remove-all-songs")
                case .stale:
                    recordOperation("remove-all-songs-deferred")
                    return
                }
            } catch {
                _ = reportTransportFailure(action: "Couldn't clear the active queue", error: error)
                recordOperation("remove-all-songs-failed", detail: error.localizedDescription)
            }
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

        let outcome = try await applyReductionWithTransport(
            reduction,
            source: "prepare-queue",
            rollbackPolicy: .full
        )
        switch outcome {
        case .applied:
            recordOperation("prepare-queue-success", detail: queueState.algorithm.rawValue)
        case .stale:
            throw ShufflePlayerError.playbackFailed("Queue changed while syncing. Try again.")
        }
    }

    // MARK: - Playback Control

    func play(algorithm: ShuffleAlgorithm? = nil) async throws {
        let reduction = try reduce(.play(algorithm: algorithm))
        guard !reduction.wasNoOp else {
            recordOperation("play-skip", detail: "empty-pool")
            return
        }

        let outcome = try await applyReductionWithTransport(
            reduction,
            source: "play",
            rollbackPolicy: .full,
            afterApply: { self.playbackObserver.clearLastObservedSongId() }
        )
        switch outcome {
        case .applied:
            recordOperation("play-success")
        case .stale:
            throw ShufflePlayerError.playbackFailed("Queue changed while syncing. Tap play again.")
        }
    }

    func pause() async {
        guard let reduction = try? reduce(.pause) else { return }
        do {
            let outcome = try await applyReductionWithTransport(
                reduction,
                source: "pause",
                rollbackPolicy: .none
            )
            if case .stale = outcome {
                return
            }
        } catch {
            _ = reportTransportFailure(action: "Couldn't pause playback", error: error)
        }
        recordOperation("pause")
    }

    func skipToNext() async throws {
        let reduction = try reduce(.skipToNext)
        let outcome = try await applyReductionWithTransport(
            reduction,
            source: "skip-next",
            rollbackPolicy: .none
        )
        if case .stale = outcome {
            throw ShufflePlayerError.playbackFailed("Queue changed while syncing. Try skipping again.")
        }
        recordOperation("skip-next")
    }

    func skipToPrevious() async throws {
        let reduction = try reduce(.skipToPrevious)
        let outcome = try await applyReductionWithTransport(
            reduction,
            source: "skip-previous",
            rollbackPolicy: .none
        )
        if case .stale = outcome {
            throw ShufflePlayerError.playbackFailed("Queue changed while syncing. Try skipping again.")
        }
        recordOperation("skip-previous")
    }

    func restartOrSkipToPrevious() async throws {
        let reduction = try reduce(.restartOrSkipToPrevious)
        let outcome = try await applyReductionWithTransport(
            reduction,
            source: "restart-or-skip-previous",
            rollbackPolicy: .none
        )
        if case .stale = outcome {
            throw ShufflePlayerError.playbackFailed("Queue changed while syncing. Try again.")
        }
        recordOperation("restart-or-skip-previous")
    }

    func togglePlayback(algorithm: ShuffleAlgorithm? = nil) async throws {
        let reduction = try reduce(.togglePlayback(algorithm: algorithm))
        guard !reduction.wasNoOp else {
            recordOperation("toggle-playback-skip", detail: "no-op")
            return
        }

        let outcome = try await applyReductionWithTransport(
            reduction,
            source: "toggle-playback",
            rollbackPolicy: .full
        )
        switch outcome {
        case .applied:
            recordOperation("toggle-playback")
        case .stale:
            throw ShufflePlayerError.playbackFailed("Queue changed while syncing. Tap play again.")
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
