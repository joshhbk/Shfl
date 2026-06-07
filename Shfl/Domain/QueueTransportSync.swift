import Foundation

// MARK: - Supporting Types

enum RollbackPolicy {
    case none
    case full
    case preservePoolAndDeferQueueBuild
}

enum TransportApplyOutcome {
    case applied
    case stale
}

struct TransportSnapshot {
    let entryCount: Int
    let currentSongId: String?
}

enum ActiveAddSyncFailureKind: String {
    case stale
    case transient
}

// MARK: - QueueTransportSync

@MainActor
final class QueueTransportSync {
    // MARK: - Dependencies

    private let playbackTransport: PlaybackTransport
    private let readQueueRevision: @MainActor () -> Int
    private let readEngineState: @MainActor () -> QueueEngineState
    private let applyReductionClosure: @MainActor (QueueEngineReduction) -> Void
    private let restoreEngineStateClosure: @MainActor (QueueEngineState) -> Void
    private let applyRecoveryIntentClosure: @MainActor (QueueIntent) -> Void
    private let setOperationNotice: @MainActor (String?) -> Void
    private let setLastObservedSongId: @MainActor (String?) -> Void
    private let clearLastObservedSongId: @MainActor () -> Void
    private let applyQueueNeedsBuildMutation: @MainActor (Bool) -> Void

    // MARK: - Owned State

    private var cachedTransportSnapshot = TransportSnapshot(entryCount: 0, currentSongId: nil)

    private lazy var transportCommandExecutor = TransportCommandExecutor { [weak self] command in
        guard let self else { return }
        try await self.executeTransportCommand(command)
    }

    // MARK: - Diagnostics State

    private var queueOperationJournal = QueueOperationJournal()
    private(set) var operationJournalVersion = 0

    // MARK: - Boundary Swap State

    private enum BoundarySwapState {
        case idle
        case armed
        case pendingSkip
        case swapping
    }

    private var boundarySwapState: BoundarySwapState = .idle
    private var boundarySwapPollingTask: Task<Void, Never>?
    private static let boundarySwapLeadTimeSeconds: TimeInterval = 0.5
    private static let boundarySwapPollIntervalNanoseconds: UInt64 = 100_000_000

    // MARK: - Active-Add Retry State

    private enum ActiveAddResyncState {
        case idle
        case draining(pendingPass: Bool)
    }

    private var activeAddResyncState: ActiveAddResyncState = .idle
    private var activeAddResyncTask: Task<Void, Never>?
    private static let activeAddRetryDelaysNanoseconds: [UInt64] = [400_000_000, 1_000_000_000]
    private static let activeAddRetryMaxPasses = 5

    // MARK: - Initialization

    init(
        playbackTransport: PlaybackTransport,
        readQueueRevision: @escaping @MainActor () -> Int,
        readEngineState: @escaping @MainActor () -> QueueEngineState,
        applyReduction: @escaping @MainActor (QueueEngineReduction) -> Void,
        restoreEngineState: @escaping @MainActor (QueueEngineState) -> Void,
        applyRecoveryIntent: @escaping @MainActor (QueueIntent) -> Void,
        setOperationNotice: @escaping @MainActor (String?) -> Void,
        setLastObservedSongId: @escaping @MainActor (String?) -> Void,
        clearLastObservedSongId: @escaping @MainActor () -> Void,
        applyQueueNeedsBuildMutation: @escaping @MainActor (Bool) -> Void
    ) {
        self.playbackTransport = playbackTransport
        self.readQueueRevision = readQueueRevision
        self.readEngineState = readEngineState
        self.applyReductionClosure = applyReduction
        self.restoreEngineStateClosure = restoreEngineState
        self.applyRecoveryIntentClosure = applyRecoveryIntent
        self.setOperationNotice = setOperationNotice
        self.setLastObservedSongId = setLastObservedSongId
        self.clearLastObservedSongId = clearLastObservedSongId
        self.applyQueueNeedsBuildMutation = applyQueueNeedsBuildMutation
    }

    // MARK: - Public API

    func applyReductionWithTransport(
        _ reduction: QueueEngineReduction,
        source: String,
        rollbackPolicy: RollbackPolicy = .full,
        staleRollbackPolicy: RollbackPolicy = .none,
        showStaleNotice: Bool = true,
        afterApply: (@MainActor () -> Void)? = nil
    ) async throws -> TransportApplyOutcome {
        let previousState = readEngineState()
        applyReductionClosure(reduction)
        afterApply?()

        do {
            try await enqueueTransportCommands(reduction.transportCommands)
            refreshTransportSnapshot()
            return .applied
        } catch {
            refreshTransportSnapshot()
            if handleStaleTransportCommand(error, source: source, showNotice: showStaleNotice) {
                rollback(to: previousState, policy: staleRollbackPolicy)
                return .stale
            }
            rollback(to: previousState, policy: rollbackPolicy)
            throw error
        }
    }

    @discardableResult
    func reportTransportFailure(action: String, error: Error) -> String {
        let message = Self.isLikelyOfflineError(error)
            ? "\(action) while offline. Reconnect and try again."
            : "\(action). Please try again."
        setOperationNotice(message)
        print("⚠️ \(action): \(error)")
        recordOperation(.transportFailure, detail: "\(action): \(error.localizedDescription)", refreshTransport: true)
        return message
    }

    @discardableResult
    func refreshTransportSnapshot() -> TransportSnapshot {
        let snapshot = TransportSnapshot(
            entryCount: playbackTransport.transportQueueEntryCount,
            currentSongId: playbackTransport.currentSongId
        )
        cachedTransportSnapshot = snapshot
        return snapshot
    }

    var transportSnapshot: TransportSnapshot { cachedTransportSnapshot }

    // MARK: - Diagnostics Public API

    var recentQueueOperations: [QueueOperationRecord] {
        _ = operationJournalVersion
        return queueOperationJournal.records
    }

    var queueInvariantCheck: QueueInvariantCheck { evaluateQueueInvariants() }

    func resetJournal() {
        queueOperationJournal = QueueOperationJournal()
        operationJournalVersion &+= 1
    }

    func recordOperation(_ operation: QueueOperationID, detail: String? = nil, refreshTransport: Bool = false) {
        if refreshTransport {
            _ = refreshTransportSnapshot()
        }
        let invariant = evaluateDomainInvariants()
        let transport = cachedTransportSnapshot
        let engineState = readEngineState()
        let record = QueueOperationRecord(
            id: UUID(),
            timestamp: Date(),
            operation: operation.rawValue,
            detail: detail,
            playbackState: playbackStateLabel(engineState.playbackState),
            poolCount: engineState.queueState.songPool.count,
            queueCount: engineState.queueState.queueOrder.count,
            currentSongId: engineState.queueState.currentSongId,
            transportEntryCount: transport.entryCount,
            transportCurrentSongId: transport.currentSongId,
            invariantHealthy: invariant.isHealthy,
            invariantReasons: invariant.reasons
        )
        queueOperationJournal.append(record)
        operationJournalVersion &+= 1
    }

    func exportQueueDiagnosticsSnapshot(trigger: String = "manual-export", detail: String? = nil) -> String {
        let invariant = evaluateQueueInvariants()
        recordOperation(.snapshotExport, detail: [trigger, detail].compactMap { $0 }.joined(separator: " | "))
        let engineState = readEngineState()
        let snapshot = QueueDiagnosticsSnapshot(
            exportedAt: Date(),
            trigger: trigger,
            detail: detail,
            playbackState: playbackStateLabel(engineState.playbackState),
            poolSongIds: engineState.queueState.songPool.map(\.id),
            queueSongIds: engineState.queueState.queueOrder.map(\.id),
            playedSongIds: engineState.queueState.playedIds.sorted(),
            currentIndex: engineState.queueState.currentIndex,
            currentSongId: engineState.queueState.currentSongId,
            transportEntryCount: invariant.transportEntryCount,
            transportCurrentSongId: invariant.transportCurrentSongId,
            invariantCheck: invariant,
            operationJournal: queueOperationJournal.records
        )

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(snapshot)
            return String(decoding: data, as: UTF8.self)
        } catch {
            recordOperation(.snapshotExportFailed, detail: error.localizedDescription)
            return "{\"error\":\"snapshot-export-failed\"}"
        }
    }

    // MARK: - Boundary Swap Public API

    func interceptResolution(_ resolution: PlaybackStateResolution) -> Bool {
        if case .swapping = boundarySwapState { return true }
        if case .armed = boundarySwapState,
           resolution.songIdToMarkPlayed != nil {
            return handleBoundarySwapAtSongBoundary(resolution: resolution)
        }
        if case .pendingSkip = boundarySwapState,
           resolution.songIdToMarkPlayed != nil {
            armBoundarySwap()
        }
        return false
    }

    func resetOnUserAction() {
        if case .swapping = boundarySwapState {} else { boundarySwapState = .idle }
    }

    func setPendingSkip() {
        if case .armed = boundarySwapState { boundarySwapState = .pendingSkip }
    }

    func rearmBoundarySwapIfNeeded(after reduction: QueueEngineReduction) {
        let engineState = readEngineState()
        guard engineState.queueNeedsBuild, engineState.playbackState.isPlaying else { return }
        guard !reductionContainsQueueSyncCommand(reduction) else { return }
        armBoundarySwap()
    }

    func cancelBoundarySwapPolling() {
        boundarySwapPollingTask?.cancel()
        boundarySwapPollingTask = nil
    }

    // MARK: - Active-Add Retry Public API

    func cancelActiveAddResyncRetry() {
        activeAddResyncState = .idle
        activeAddResyncTask?.cancel()
        activeAddResyncTask = nil
    }

    func applyActiveAddReductionWithRetry(
        _ reduction: QueueEngineReduction,
        source: String,
        successOperation: QueueOperationID,
        degradedOperation: QueueOperationID,
        successDetail: String
    ) async {
        do {
            let outcome = try await applyReductionWithTransport(
                reduction,
                source: source,
                rollbackPolicy: .preservePoolAndDeferQueueBuild,
                staleRollbackPolicy: .preservePoolAndDeferQueueBuild,
                showStaleNotice: false
            )
            switch outcome {
            case .applied:
                recordOperation(successOperation, detail: successDetail)
            case .stale:
                scheduleActiveAddResyncRetry(source: source, failureKind: .stale)
                recordOperation(degradedOperation, detail: "\(successDetail), reason=stale")
            }
        } catch {
            let failureReason: String
            if Self.isTransientAddSyncError(error) {
                scheduleActiveAddResyncRetry(source: source, failureKind: .transient)
                failureReason = "transient"
            } else {
                applyQueueNeedsBuildMutation(true)
                recordOperation(.activeAddSyncNonTransientFailed, detail: "source=\(source), error=\(error.localizedDescription)")
                failureReason = "non-transient"
            }
            recordOperation(degradedOperation, detail: "\(successDetail), reason=\(failureReason)")
        }
    }

    func applyNonActiveAddReduction(
        _ reduction: QueueEngineReduction,
        context: NonActiveAddReductionContext,
        successDetail: String,
        failureDetail: String
    ) async throws {
        do {
            let outcome = try await applyReductionWithTransport(
                reduction,
                source: context.source,
                rollbackPolicy: .preservePoolAndDeferQueueBuild
            )
            switch outcome {
            case .applied:
                recordOperation(context.successOperation, detail: successDetail)
            case .stale:
                recordOperation(context.deferredOperation, detail: successDetail)
            }
        } catch {
            let message = reportTransportFailure(action: context.actionDescription, error: error)
            recordOperation(context.failureOperation, detail: failureDetail)
            throw ShufflePlayerError.playbackFailed(message)
        }
    }

    /// Stops playback, applies corrected reduction, and pauses immediately for boundary swap.
    func enforceDomainInvariants(context: String) {
        let engineState = readEngineState()
        let queueIds = engineState.queueState.queueOrder.map(\.id)
        let queueIdSet = Set(queueIds)
        let poolIdSet = Set(engineState.queueState.songPool.map(\.id))
        let hasValidCurrent = !engineState.queueState.hasQueue || engineState.queueState.currentSong != nil
        let queueMembershipIsValid: Bool
        if engineState.queueState.hasQueue {
            if engineState.queueNeedsBuild {
                queueMembershipIsValid = true
            } else {
                queueMembershipIsValid = queueIds.count == queueIdSet.count && queueIdSet == poolIdSet
            }
        } else {
            queueMembershipIsValid = engineState.queueState.isEmpty || engineState.queueNeedsBuild || !engineState.playbackState.isActive
        }
        let isHealthy = queueMembershipIsValid && hasValidCurrent

        guard !engineState.queueState.isEmpty else { return }
        guard !isHealthy else { return }

        if !engineState.queueNeedsBuild {
            applyRecoveryIntentClosure(.recoverFromInvariantViolation)
        }

        setOperationNotice("Queue sync issue detected. Rebuilding queue.")
        recordOperation(.invariantViolation, detail: "context=\(context), pool=\(engineState.queueState.songPool.count), queue=\(engineState.queueState.queueOrder.count)")
    }

    // MARK: - Song Addition Context

    struct NonActiveAddReductionContext {
        let source: String
        let actionDescription: String
        let successOperation: QueueOperationID
        let deferredOperation: QueueOperationID
        let failureOperation: QueueOperationID
    }

    // MARK: - Transport Command Execution

    private func executeTransportCommand(_ command: TransportCommand) async throws {
        let currentRevision = readQueueRevision()
        guard command.revision == currentRevision else {
            throw TransportCommandExecutionError.staleRevision(
                commandRevision: command.revision,
                queueRevision: currentRevision
            )
        }
        switch command {
        case .setQueue(let songs, _):
            try await playbackTransport.setQueue(songs: songs)
        case .replaceQueue(let queue, let startAtSongId, let policy, _):
            try await playbackTransport.replaceQueue(queue: queue, startAtSongId: startAtSongId, policy: policy)
        case .play:
            try await playbackTransport.play()
        case .pause:
            await playbackTransport.pause()
        case .skipToNext:
            try await playbackTransport.skipToNext()
        case .skipToPrevious:
            try await playbackTransport.skipToPrevious()
        case .restartOrSkipToPrevious:
            try await playbackTransport.restartOrSkipToPrevious()
        }
    }

    private func enqueueTransportCommands(_ commands: [TransportCommand]) async throws {
        try await transportCommandExecutor.enqueue(commands)
    }

    // MARK: - Stale Detection & Recovery

    @discardableResult
    private func handleStaleTransportCommand(_ error: Error, source: String, showNotice: Bool = true) -> Bool {
        guard case let TransportCommandExecutionError.staleRevision(commandRevision, queueRevision) = error else {
            return false
        }
        applyRecoveryIntentClosure(.recoverFromStaleTransport)
        if showNotice {
            setOperationNotice("Queue changed while syncing. Rebuilding queue.")
        }
        recordOperation(.transportCommandStale, detail: "source=\(source), commandRevision=\(commandRevision), queueRevision=\(queueRevision)")
        return true
    }

    // MARK: - Rollback

    private func restoreEngineState(_ state: QueueEngineState) {
        restoreEngineStateClosure(state)
    }

    private func rollback(to previousState: QueueEngineState, policy: RollbackPolicy) {
        switch policy {
        case .none:
            return
        case .full:
            restoreEngineState(previousState)
        case .preservePoolAndDeferQueueBuild:
            let currentState = readEngineState()
            let newQueueState = QueueState(
                songPool: currentState.queueState.songPool,
                queueOrder: previousState.queueState.queueOrder,
                playedIds: previousState.queueState.playedIds,
                currentIndex: previousState.queueState.currentIndex,
                algorithm: previousState.queueState.algorithm
            )
            let restoredState = QueueEngineState(
                queueState: newQueueState,
                playbackState: previousState.playbackState,
                revision: previousState.revision,
                queueNeedsBuild: true
            )
            restoreEngineState(restoredState)
        }
    }

    // MARK: - Diagnostics Implementation

    private struct DomainInvariantSnapshot {
        let poolIds: [String]
        let queueIds: [String]
        let poolIdSet: Set<String>
        let queueIdSet: Set<String>
        let queueParityExpected: Bool
        let playbackCurrentSongId: String?
        let reasons: [String]
        var isHealthy: Bool { reasons.isEmpty }
    }

    private func playbackStateLabel(_ state: PlaybackState) -> String {
        switch state {
        case .empty: return "empty"
        case .stopped: return "stopped"
        case .loading: return "loading"
        case .playing: return "playing"
        case .paused: return "paused"
        case .error(let error): return "error(\(error.localizedDescription))"
        }
    }

    private func domainInvariantReasons(
        poolIds: [String], queueIds: [String],
        poolIdSet: Set<String>, queueIdSet: Set<String>,
        queueParityExpected: Bool, playbackCurrentSongId: String?
    ) -> [String] {
        var reasons: [String] = []
        let engineState = readEngineState()
        if engineState.queueState.hasQueue && queueIds.count != queueIdSet.count {
            reasons.append("duplicate-queue-ids")
        }
        if queueParityExpected && poolIdSet != queueIdSet {
            reasons.append("pool-queue-membership-mismatch")
        }
        if queueParityExpected && queueIds.count != poolIds.count {
            reasons.append("pool-queue-count-mismatch")
        }
        if engineState.queueState.hasQueue && engineState.queueState.currentSong == nil {
            reasons.append("current-index-out-of-bounds")
        }
        if let playbackCurrentSongId, !poolIdSet.contains(playbackCurrentSongId) {
            reasons.append("playback-song-not-in-pool")
        }
        return reasons
    }

    private func makeDomainInvariantSnapshot() -> DomainInvariantSnapshot {
        let engineState = readEngineState()
        let poolIds = engineState.queueState.songPool.map(\.id)
        let queueIds = engineState.queueState.queueOrder.map(\.id)
        let poolIdSet = Set(poolIds)
        let queueIdSet = Set(queueIds)
        let queueParityExpected = !engineState.queueNeedsBuild && (engineState.queueState.hasQueue || engineState.playbackState.isActive)
        let playbackCurrentSongId = engineState.playbackState.currentSongId
        let reasons = domainInvariantReasons(
            poolIds: poolIds, queueIds: queueIds,
            poolIdSet: poolIdSet, queueIdSet: queueIdSet,
            queueParityExpected: queueParityExpected,
            playbackCurrentSongId: playbackCurrentSongId
        )
        return DomainInvariantSnapshot(
            poolIds: poolIds, queueIds: queueIds,
            poolIdSet: poolIdSet, queueIdSet: queueIdSet,
            queueParityExpected: queueParityExpected,
            playbackCurrentSongId: playbackCurrentSongId,
            reasons: reasons
        )
    }

    private func evaluateDomainInvariants() -> (isHealthy: Bool, reasons: [String]) {
        let snapshot = makeDomainInvariantSnapshot()
        return (isHealthy: snapshot.isHealthy, reasons: snapshot.reasons)
    }

    private func evaluateQueueInvariants() -> QueueInvariantCheck {
        let snapshot = makeDomainInvariantSnapshot()
        let engineState = readEngineState()
        let queueHasUniqueIDs = !engineState.queueState.hasQueue || snapshot.queueIds.count == snapshot.queueIdSet.count
        let poolAndQueueMembershipMatch = !snapshot.queueParityExpected || snapshot.poolIdSet == snapshot.queueIdSet
        let transportSnap = refreshTransportSnapshot()
        let transportEntryCountMatchesQueue = !snapshot.queueParityExpected || transportSnap.entryCount == snapshot.queueIds.count
        let transportCurrentMatchesDomain = !snapshot.queueParityExpected
            || transportSnap.currentSongId == engineState.queueState.currentSongId
            || snapshot.playbackCurrentSongId == engineState.queueState.currentSongId

        var reasons = snapshot.reasons
        if !transportEntryCountMatchesQueue { reasons.append("transport-entry-count-mismatch") }
        if !transportCurrentMatchesDomain { reasons.append("transport-current-song-mismatch") }

        return QueueInvariantCheck(
            isHealthy: reasons.isEmpty,
            reasons: reasons,
            poolCount: engineState.queueState.songPool.count,
            queueCount: engineState.queueState.queueOrder.count,
            playedCount: engineState.queueState.playedIds.count,
            currentIndex: engineState.queueState.currentIndex,
            domainCurrentSongId: engineState.queueState.currentSongId,
            playbackCurrentSongId: snapshot.playbackCurrentSongId,
            transportEntryCount: transportSnap.entryCount,
            transportCurrentSongId: transportSnap.currentSongId,
            queueHasUniqueIDs: queueHasUniqueIDs,
            poolAndQueueMembershipMatch: poolAndQueueMembershipMatch,
            transportEntryCountMatchesQueue: transportEntryCountMatchesQueue,
            transportCurrentMatchesDomain: transportCurrentMatchesDomain
        )
    }

    // MARK: - Boundary Swap Implementation

    private func armBoundarySwap() {
        guard boundarySwapState != .swapping else { return }
        boundarySwapState = .armed
        let engineState = readEngineState()
        let nextIndex = engineState.queueState.currentIndex + 1
        if nextIndex < engineState.queueState.queueOrder.count {
            ArtworkCache.shared.requestArtwork(for: engineState.queueState.queueOrder[nextIndex].id)
        }
        startBoundarySwapPolling()
    }

    private func startBoundarySwapPolling() {
        boundarySwapPollingTask?.cancel()
        boundarySwapPollingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, case .armed = self.boundarySwapState else { return }
                guard self.readEngineState().playbackState.isPlaying else {
                    try? await Task.sleep(nanoseconds: Self.boundarySwapPollIntervalNanoseconds)
                    continue
                }
                let duration = self.playbackTransport.currentSongDuration
                let currentTime = self.playbackTransport.currentPlaybackTime
                let remaining = duration - currentTime
                if duration > 0 && currentTime > 0 && remaining <= Self.boundarySwapLeadTimeSeconds {
                    self.triggerPreemptiveBoundarySwap()
                    return
                }
                try? await Task.sleep(nanoseconds: Self.boundarySwapPollIntervalNanoseconds)
            }
        }
    }

    private func triggerPreemptiveBoundarySwap() {
        guard case .armed = boundarySwapState else { return }
        let engineState = readEngineState()
        let nextIndex = engineState.queueState.currentIndex + 1
        guard nextIndex < engineState.queueState.queueOrder.count else {
            boundarySwapState = .idle
            return
        }
        performBoundarySwapSequence(
            nextSong: engineState.queueState.queueOrder[nextIndex],
            songIdToMarkPlayed: engineState.queueState.currentSongId,
            detail: "preemptive"
        )
    }

    private func handleBoundarySwapAtSongBoundary(resolution: PlaybackStateResolution) -> Bool {
        let engineState = readEngineState()
        let nextIndex = engineState.queueState.currentIndex + 1
        guard nextIndex < engineState.queueState.queueOrder.count else {
            boundarySwapState = .idle
            return false
        }
        performBoundarySwapSequence(
            nextSong: engineState.queueState.queueOrder[nextIndex],
            songIdToMarkPlayed: resolution.songIdToMarkPlayed,
            detail: "reactive"
        )
        return true
    }

    private func performBoundarySwapSequence(nextSong: Song, songIdToMarkPlayed: String?, detail: String) {
        cancelBoundarySwapPolling()
        let enrichedSong: Song
        if nextSong.artworkURL == nil,
           let cachedURL = ArtworkCache.shared.artworkURL(for: nextSong.id) {
            enrichedSong = Song(
                id: nextSong.id, title: nextSong.title, artist: nextSong.artist,
                albumTitle: nextSong.albumTitle, artworkURL: cachedURL,
                playCount: nextSong.playCount, lastPlayedDate: nextSong.lastPlayedDate
            )
        } else {
            enrichedSong = nextSong
        }
        let correctedResolution = PlaybackStateResolution(
            resolvedState: .playing(enrichedSong),
            resolvedSongId: enrichedSong.id,
            shouldUpdateCurrentSong: true,
            songIdToMarkPlayed: songIdToMarkPlayed,
            shouldClearHistory: false
        )
        do {
            let reduction = try reduce(intent: .playbackResolution(correctedResolution))
            applyReductionClosure(reduction)
        } catch {
            recordOperation(.playbackResolutionReducerFailed, detail: "\(detail)-boundary-swap: \(error.localizedDescription)")
            boundarySwapState = .idle
            return
        }
        recordOperation(.boundarySyncStarted, detail: "\(detail), nextSong=\(nextSong.id)")
        boundarySwapState = .swapping
        playbackTransport.pauseImmediately()
        Task { @MainActor [weak self] in
            await self?.executeBoundarySwap(nextSongId: nextSong.id)
        }
    }

    private func reduce(intent: QueueIntent) throws -> QueueEngineReduction {
        try QueueEngineReducer.reduce(state: readEngineState(), intent: intent)
    }

    private func executeBoundarySwap(nextSongId: String) async {
        defer {
            boundarySwapState = .idle
            if readEngineState().queueNeedsBuild {
                armBoundarySwap()
                scheduleActiveAddResyncRetry(source: "boundary-swap-followup", failureKind: .stale)
            }
        }
        do {
            let reduction = try reduce(intent: .syncDeferredTransport)
            guard !reduction.wasNoOp else { return }
            let outcome = try await applyReductionWithTransport(
                reduction, source: "boundary-swap",
                rollbackPolicy: .preservePoolAndDeferQueueBuild,
                staleRollbackPolicy: .preservePoolAndDeferQueueBuild,
                showStaleNotice: false
            )
            switch outcome {
            case .applied:
                setLastObservedSongId(nextSongId)
                playbackTransport.seek(to: 0)
                recordOperation(.deferredTransportRebuilt, detail: "boundary-swap")
            case .stale:
                scheduleActiveAddResyncRetry(source: "boundary-swap", failureKind: .stale)
            }
        } catch {
            if Self.isTransientAddSyncError(error) {
                scheduleActiveAddResyncRetry(source: "boundary-swap", failureKind: .transient)
            } else {
                recordOperation(.activeAddSyncNonTransientFailed, detail: "source=boundary-swap, error=\(error.localizedDescription)")
            }
        }
    }

    private func reductionContainsQueueSyncCommand(_ reduction: QueueEngineReduction) -> Bool {
        reduction.transportCommands.contains { command in
            switch command { case .setQueue, .replaceQueue: return true; default: return false }
        }
    }

    // MARK: - Active-Add Retry Implementation

    private func scheduleActiveAddResyncRetry(source: String, failureKind: ActiveAddSyncFailureKind) {
        applyQueueNeedsBuildMutation(true)
        activeAddResyncState = .draining(pendingPass: true)
        recordOperation(.activeAddSyncRetryScheduled, detail: "source=\(source), reason=\(failureKind.rawValue)")
        guard activeAddResyncTask == nil else { return }
        activeAddResyncTask = Task { @MainActor [weak self] in
            await self?.drainActiveAddResyncRetries()
        }
    }

    private func drainActiveAddResyncRetries() async {
        defer { activeAddResyncTask = nil; activeAddResyncState = .idle }
        var passCount = 0
        while passCount < Self.activeAddRetryMaxPasses {
            guard !Task.isCancelled else { break }
            guard case .draining(let pendingPass) = activeAddResyncState, pendingPass else { break }
            activeAddResyncState = .draining(pendingPass: false)
            passCount += 1
            let didSync = await executeActiveAddResyncAttemptPass()
            guard !Task.isCancelled else { break }
            if !didSync { recordOperation(.activeAddSyncRetryExhausted) }
        }
        if case .draining(let pendingPass) = activeAddResyncState, pendingPass && !Task.isCancelled {
            recordOperation(.activeAddSyncRetryExhausted, detail: "pass-cap=\(Self.activeAddRetryMaxPasses)")
        }
    }

    private func executeActiveAddResyncAttemptPass() async -> Bool {
        let attemptCount = Self.activeAddRetryDelaysNanoseconds.count + 1
        var didSync = false
        attempts: for attempt in 1...attemptCount {
            guard !Task.isCancelled else { break }
            recordOperation(.activeAddSyncRetryAttempt, detail: "attempt=\(attempt)")
            do {
                let reduction = try reduce(intent: .resyncActiveAddTransport)
                guard !reduction.wasNoOp else { didSync = true; break }
                let outcome = try await applyReductionWithTransport(
                    reduction, source: "active-add-retry",
                    rollbackPolicy: .preservePoolAndDeferQueueBuild,
                    staleRollbackPolicy: .preservePoolAndDeferQueueBuild,
                    showStaleNotice: false
                )
                switch outcome {
                case .applied:
                    recordOperation(.activeAddSyncRetrySuccess, detail: "attempt=\(attempt)")
                    cancelBoundarySwapPolling()
                    didSync = true; break attempts
                case .stale:
                    if attempt == attemptCount { break attempts }
                    try? await Task.sleep(nanoseconds: Self.activeAddRetryDelaysNanoseconds[attempt - 1])
                    guard !Task.isCancelled else { break attempts }; continue
                }
            } catch {
                if !Self.isTransientAddSyncError(error) {
                    recordOperation(.activeAddSyncNonTransientFailed, detail: "attempt=\(attempt), error=\(error.localizedDescription)")
                    break attempts
                }
                if attempt == attemptCount { break attempts }
                try? await Task.sleep(nanoseconds: Self.activeAddRetryDelaysNanoseconds[attempt - 1])
                guard !Task.isCancelled else { break attempts }
            }
        }
        return didSync
    }

    // MARK: - Error Classification

    static func isLikelyOfflineError(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else { return false }
        return [NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost, NSURLErrorTimedOut,
                NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost, NSURLErrorInternationalRoamingOff,
                NSURLErrorDataNotAllowed, NSURLErrorCallIsActive].contains(nsError.code)
    }

    static func isTransientAddSyncError(_ error: Error) -> Bool {
        if case TransportCommandExecutionError.staleRevision = error { return true }
        return isLikelyOfflineError(error)
    }
}