import Foundation

@Observable
@MainActor
final class ShufflePlayer {
    @ObservationIgnored private let musicService: MusicService
    @ObservationIgnored private let playbackObserver: PlaybackStateObserver
    @ObservationIgnored private lazy var transportCommandExecutor = TransportCommandExecutor { [weak self] command in
        guard let self else { return }
        try await self.executeTransportCommand(command)
    }
    @ObservationIgnored private var cachedTransportSnapshot = TransportSnapshot(entryCount: 0, currentSongId: nil)
    @ObservationIgnored private var activeAddResyncTask: Task<Void, Never>?
    @ObservationIgnored private var activeAddResyncState: ActiveAddResyncState = .idle
    @ObservationIgnored private var boundarySwapState: BoundarySwapState = .idle
    @ObservationIgnored private var boundarySwapPollingTask: Task<Void, Never>?

    /// Single source of truth for queue state
    private(set) var queueState: QueueState = .empty

    /// Current playback state from MusicKit
    private(set) var playbackState: PlaybackState = .empty

    /// Monotonic revision used to gate stale transport commands.
    private(set) var queueRevision: Int = 0

    /// Whether playback should rebuild transport queue before attempting play.
    private(set) var queueNeedsBuild = true

    /// Rolling operation journal for queue diagnostics.
    @ObservationIgnored private(set) var queueOperationJournal = QueueOperationJournal()
    private(set) var operationJournalVersion = 0

    /// Non-blocking operation notice for queue/transport sync failures.
    private(set) var operationNotice: String?

    // Retry orchestration state intentionally lives outside the reducer.
    // It controls when we reinvoke reducer intents, not domain queue semantics.
    private enum ActiveAddResyncState {
        case idle
        case draining(pendingPass: Bool)
    }

    /// Coordinates deferred transport sync when active playback needs a queue rebuild.
    /// Instead of rebuilding the MusicKit queue mid-song (causing audible interruption),
    /// the swap is deferred to the natural song boundary where a brief silence is expected.
    private enum BoundarySwapState {
        /// No deferred transport sync needed.
        case idle
        /// A queue mutation was deferred during active playback. Waiting for song boundary.
        case armed
        /// Armed, but the user just skipped. The next observer transition is from the skip,
        /// not a natural song boundary — process it normally then return to .armed.
        case pendingSkip
        /// Currently executing the boundary swap (pause → replace → play).
        /// Observer emissions are suppressed.
        case swapping
    }

    // MARK: - Computed Properties

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
    var recentQueueOperations: [QueueOperationRecord] {
        _ = operationJournalVersion
        return queueOperationJournal.records
    }

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
        recordOperation(.playerInit)
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
        // Suppress all observer emissions while a boundary swap is in progress.
        if case .swapping = boundarySwapState { return }

        // Boundary swap: detect natural song transition while armed.
        // Check BEFORE applying the normal resolution so domain state still points
        // to the previous song for next-song lookup.
        if case .armed = boundarySwapState,
           resolution.songIdToMarkPlayed != nil {
            performBoundarySwap(resolution: resolution)
            return
        }

        // Skip handling: the skip's observer transition is processed normally,
        // then we return to armed for the next natural boundary.
        if case .pendingSkip = boundarySwapState,
           resolution.songIdToMarkPlayed != nil {
            armBoundarySwap()
        }

        do {
            let reduction = try reduce(.playbackResolution(resolution))
            if !reduction.transportCommands.isEmpty {
#if DEBUG
                assertionFailure("playbackResolution emitted transport commands")
#endif
                recordOperation(
                    .playbackResolutionIllegalTransport,
                    detail: "count=\(reduction.transportCommands.count)"
                )
            }
            applyReduction(reduction)
        } catch {
#if DEBUG
            if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
                assertionFailure("Unexpected playbackResolution reducer failure: \(error)")
            }
#endif
            recordOperation(.playbackResolutionReducerFailed, detail: error.localizedDescription)
        }
        if let seek = resolution.pendingSeekConsumed {
            musicService.seek(to: seek.position)
        }
        recordOperation(
            .playbackResolution,
            detail: "state=\(playbackStateLabel(resolution.resolvedState)), song=\(resolution.resolvedSongId ?? "nil")"
        )
    }

    func clearOperationNotice() {
        operationNotice = nil
        recordOperation(.clearOperationNotice)
    }

    /// Debug-only escape hatch to return queue and diagnostics to a clean baseline.
    func hardResetQueueForDebug() async {
        cancelActiveAddResyncRetry()
        cancelBoundarySwapPolling()
        await removeAllSongs()
        queueOperationJournal = QueueOperationJournal()
        operationJournalVersion &+= 1
        operationNotice = nil
        playbackObserver.clearLastObservedSongId()
        playbackObserver.clearPendingRestoreSeek()
        recordOperation(.hardResetQueue)
    }

    private func reportTransportFailure(action: String, error: Error) -> String {
        let message = Self.isLikelyOfflineError(error)
            ? "\(action) while offline. Reconnect and try again."
            : "\(action). Please try again."
        operationNotice = message
        print("⚠️ \(action): \(error)")
        recordOperation(
            .transportFailure,
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

    private enum ActiveAddSyncFailureKind: String {
        case stale
        case transient
    }

    private static let activeAddRetryDelaysNanoseconds: [UInt64] = [
        400_000_000,
        1_000_000_000
    ]
    private static let activeAddRetryMaxPasses = 5

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

    /// Serializes transport command batches without building an unbounded linked task chain.
    @MainActor
    private final class TransportCommandExecutor {
        typealias CommandRunner = (TransportCommand) async throws -> Void

        private struct Batch {
            let commands: [TransportCommand]
            let continuation: CheckedContinuation<Void, Error>
        }

        private let runCommand: CommandRunner
        private var pendingBatches: [Batch] = []
        private var isDraining = false

        init(runCommand: @escaping CommandRunner) {
            self.runCommand = runCommand
        }

        func enqueue(_ commands: [TransportCommand]) async throws {
            guard !commands.isEmpty else { return }

            try await withCheckedThrowingContinuation { continuation in
                pendingBatches.append(Batch(commands: commands, continuation: continuation))
                guard !isDraining else { return }
                isDraining = true
                Task { @MainActor [weak self] in
                    await self?.drain()
                }
            }
        }

        private func drain() async {
            while !pendingBatches.isEmpty {
                let batch = pendingBatches.removeFirst()
                do {
                    for command in batch.commands {
                        try await runCommand(command)
                    }
                    batch.continuation.resume(returning: ())
                } catch {
                    batch.continuation.resume(throwing: error)
                }
            }

            isDraining = false
        }
    }

    @discardableResult
    private func handleStaleTransportCommand(_ error: Error, source: String, showNotice: Bool = true) -> Bool {
        guard case let TransportCommandExecutionError.staleRevision(commandRevision, queueRevision) = error else {
            return false
        }

        applyRecoveryIntent(.recoverFromStaleTransport)
        if showNotice {
            operationNotice = "Queue changed while syncing. Rebuilding queue."
        }
        recordOperation(
            .transportCommandStale,
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

    private static func isTransientAddSyncError(_ error: Error) -> Bool {
        if case TransportCommandExecutionError.staleRevision = error {
            return true
        }
        return isLikelyOfflineError(error)
    }

    // MARK: - Boundary Swap

    /// Pause preemptively before end-of-song to avoid any playback of the wrong next song.
    private static let boundarySwapLeadTimeSeconds: TimeInterval = 0.5
    private static let boundarySwapPollIntervalNanoseconds: UInt64 = 100_000_000 // 100ms

    private func armBoundarySwap() {
        guard boundarySwapState != .swapping else { return }
        boundarySwapState = .armed
        // Preload artwork for the next song so it's cached before the swap fires.
        // Pool songs have artworkURL: nil and may never have been displayed in a view.
        let nextIndex = queueState.currentIndex + 1
        if nextIndex < queueState.queueOrder.count {
            ArtworkCache.shared.requestArtwork(for: queueState.queueOrder[nextIndex].id)
        }
        startBoundarySwapPolling()
    }

    private func startBoundarySwapPolling() {
        boundarySwapPollingTask?.cancel()
        boundarySwapPollingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, case .armed = self.boundarySwapState else { return }

                // Only poll when actively playing. Paused state doesn't advance
                // playback time, so polling would spin uselessly.
                guard self.playbackState.isPlaying else {
                    try? await Task.sleep(nanoseconds: Self.boundarySwapPollIntervalNanoseconds)
                    continue
                }

                let duration = self.musicService.currentSongDuration
                let currentTime = self.musicService.currentPlaybackTime
                let remaining = duration - currentTime

                if duration > 0 && currentTime > 0 && remaining <= Self.boundarySwapLeadTimeSeconds {
                    self.triggerPreemptiveBoundarySwap()
                    return
                }

                try? await Task.sleep(nanoseconds: Self.boundarySwapPollIntervalNanoseconds)
            }
        }
    }

    private func cancelBoundarySwapPolling() {
        boundarySwapPollingTask?.cancel()
        boundarySwapPollingTask = nil
    }

    /// Preemptive path: polling detected the song is about to end.
    private func triggerPreemptiveBoundarySwap() {
        guard case .armed = boundarySwapState else { return }

        let nextIndex = queueState.currentIndex + 1
        guard nextIndex < queueState.queueOrder.count else {
            // End of queue — let playback finish naturally.
            boundarySwapState = .idle
            return
        }

        startBoundarySwapSequence(
            nextSong: queueState.queueOrder[nextIndex],
            songIdToMarkPlayed: queueState.currentSongId,
            detail: "preemptive"
        )
    }

    /// Reactive path: observer detected a song transition while armed.
    private func performBoundarySwap(resolution: PlaybackStateResolution) {
        let nextIndex = queueState.currentIndex + 1
        guard nextIndex < queueState.queueOrder.count else {
            // End of queue — no next song to swap to. Apply original resolution normally.
            boundarySwapState = .idle
            applyResolution(resolution)
            return
        }

        startBoundarySwapSequence(
            nextSong: queueState.queueOrder[nextIndex],
            songIdToMarkPlayed: resolution.songIdToMarkPlayed,
            detail: "reactive"
        )
    }

    /// Shared core: apply corrected resolution, pause immediately, launch async queue rebuild.
    private func startBoundarySwapSequence(nextSong: Song, songIdToMarkPlayed: String?, detail: String) {
        cancelBoundarySwapPolling()

        // Enrich pool song with cached artwork URL so the UI doesn't flash a placeholder.
        // Pool songs have artworkURL: nil; normal transitions get it from MusicKit's playback state.
        let enrichedSong: Song
        if nextSong.artworkURL == nil,
           let cachedURL = ArtworkCache.shared.artworkURL(for: nextSong.id) {
            enrichedSong = Song(
                id: nextSong.id,
                title: nextSong.title,
                artist: nextSong.artist,
                albumTitle: nextSong.albumTitle,
                artworkURL: cachedURL,
                playCount: nextSong.playCount,
                lastPlayedDate: nextSong.lastPlayedDate
            )
        } else {
            enrichedSong = nextSong
        }

        let correctedResolution = PlaybackStateResolution(
            resolvedState: .playing(enrichedSong),
            resolvedSongId: enrichedSong.id,
            shouldUpdateCurrentSong: true,
            songIdToMarkPlayed: songIdToMarkPlayed,
            shouldClearHistory: false,
            pendingSeekConsumed: nil
        )
        do {
            let reduction = try reduce(.playbackResolution(correctedResolution))
            applyReduction(reduction)
        } catch {
            recordOperation(.playbackResolutionReducerFailed, detail: "\(detail)-boundary-swap: \(error.localizedDescription)")
            boundarySwapState = .idle
            return
        }

        recordOperation(.boundarySyncStarted, detail: "\(detail), nextSong=\(nextSong.id)")
        boundarySwapState = .swapping

        // Stop audio immediately — MusicKit's pause() is synchronous under the hood.
        musicService.pauseImmediately()

        Task { @MainActor [weak self] in
            await self?.executeBoundarySwap(nextSongId: nextSong.id)
        }
    }

    private func executeBoundarySwap(nextSongId: String) async {
        defer {
            if queueNeedsBuild {
                armBoundarySwap()
            } else {
                boundarySwapState = .idle
            }
        }

        do {
            let reduction = try reduce(.syncDeferredTransport)
            guard !reduction.wasNoOp else { return }

            let outcome = try await applyReductionWithTransport(
                reduction,
                source: "boundary-swap",
                rollbackPolicy: .preservePoolAndDeferQueueBuild,
                staleRollbackPolicy: .preservePoolAndDeferQueueBuild,
                showStaleNotice: false
            )
            switch outcome {
            case .applied:
                playbackObserver.setLastObservedSongId(nextSongId)
                musicService.seek(to: 0)
                recordOperation(.deferredTransportRebuilt, detail: "boundary-swap")
            case .stale:
                scheduleActiveAddResyncRetry(source: "boundary-swap", failureKind: .stale)
            }
        } catch {
            if Self.isTransientAddSyncError(error) {
                scheduleActiveAddResyncRetry(source: "boundary-swap", failureKind: .transient)
            } else {
                recordOperation(
                    .activeAddSyncNonTransientFailed,
                    detail: "source=boundary-swap, error=\(error.localizedDescription)"
                )
            }
        }
    }

    private func cancelActiveAddResyncRetry() {
        activeAddResyncState = .idle
        activeAddResyncTask?.cancel()
        activeAddResyncTask = nil
    }

    private func scheduleActiveAddResyncRetry(source: String, failureKind: ActiveAddSyncFailureKind) {
        applyQueueNeedsBuildMutation(true)
        activeAddResyncState = .draining(pendingPass: true)
        recordOperation(
            .activeAddSyncRetryScheduled,
            detail: "source=\(source), reason=\(failureKind.rawValue)"
        )

        guard activeAddResyncTask == nil else { return }
        activeAddResyncTask = Task { @MainActor [weak self] in
            await self?.drainActiveAddResyncRetries()
        }
    }

    private func drainActiveAddResyncRetries() async {
        defer {
            activeAddResyncTask = nil
            activeAddResyncState = .idle
        }

        var passCount = 0
        while passCount < Self.activeAddRetryMaxPasses {
            guard !Task.isCancelled else { break }
            guard case .draining(let pendingPass) = activeAddResyncState, pendingPass else { break }
            activeAddResyncState = .draining(pendingPass: false)
            passCount += 1

            let didSync = await executeActiveAddResyncAttemptPass()

            guard !Task.isCancelled else { break }
            if !didSync {
                recordOperation(.activeAddSyncRetryExhausted)
            }
        }

        if case .draining(let pendingPass) = activeAddResyncState,
           pendingPass && !Task.isCancelled {
            recordOperation(
                .activeAddSyncRetryExhausted,
                detail: "pass-cap=\(Self.activeAddRetryMaxPasses)"
            )
        }
    }

    private func executeActiveAddResyncAttemptPass() async -> Bool {
        let attemptCount = Self.activeAddRetryDelaysNanoseconds.count + 1
        var didSync = false

        attempts: for attempt in 1...attemptCount {
            guard !Task.isCancelled else { break }
            recordOperation(.activeAddSyncRetryAttempt, detail: "attempt=\(attempt)")
            do {
                // Recompute from the latest state each attempt. @MainActor serialization and
                // revision fencing ensure interleavings fail stale instead of applying incorrectly.
                let reduction = try reduce(.resyncActiveAddTransport)
                guard !reduction.wasNoOp else {
                    didSync = true
                    break
                }

                let outcome = try await applyReductionWithTransport(
                    reduction,
                    source: "active-add-retry",
                    rollbackPolicy: .preservePoolAndDeferQueueBuild,
                    staleRollbackPolicy: .preservePoolAndDeferQueueBuild,
                    showStaleNotice: false
                )
                switch outcome {
                case .applied:
                    recordOperation(.activeAddSyncRetrySuccess, detail: "attempt=\(attempt)")
                    // Disarm boundary swap — the retry already synced the transport.
                    if case .armed = boundarySwapState {
                        cancelBoundarySwapPolling()
                        boundarySwapState = .idle
                    }
                    didSync = true
                    break attempts
                case .stale:
                    if attempt == attemptCount {
                        break attempts
                    }
                    let delay = Self.activeAddRetryDelaysNanoseconds[attempt - 1]
                    try? await Task.sleep(nanoseconds: delay)
                    guard !Task.isCancelled else { break attempts }
                    continue
                }
            } catch {
                if !Self.isTransientAddSyncError(error) {
                    recordOperation(
                        .activeAddSyncNonTransientFailed,
                        detail: "attempt=\(attempt), error=\(error.localizedDescription)"
                    )
                    break attempts
                }

                if attempt == attemptCount {
                    break attempts
                }

                let delay = Self.activeAddRetryDelaysNanoseconds[attempt - 1]
                try? await Task.sleep(nanoseconds: delay)
                guard !Task.isCancelled else { break attempts }
            }
        }

        return didSync
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
            queueRevision = previousState.revision
            queueNeedsBuild = true
        }
    }

    private func applyReductionWithTransport(
        _ reduction: QueueEngineReduction,
        source: String,
        rollbackPolicy: RollbackPolicy = .full,
        staleRollbackPolicy: RollbackPolicy = .none,
        showStaleNotice: Bool = true,
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
            if handleStaleTransportCommand(error, source: source, showNotice: showStaleNotice) {
                rollback(to: previousState, policy: staleRollbackPolicy)
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

        // Any invariant break should push the system into an explicit rebuild path.
        if !queueNeedsBuild {
            applyRecoveryIntent(.recoverFromInvariantViolation)
        }

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
            .invariantViolation,
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
        try await transportCommandExecutor.enqueue(commands)
    }

    private func reduce(_ intent: QueueIntent) throws -> QueueEngineReduction {
        try QueueEngineReducer.reduce(state: engineState, intent: intent)
    }

    private func applyRecoveryIntent(_ intent: QueueIntent) {
        do {
            let reduction = try reduce(intent)
            guard !reduction.wasNoOp else { return }
            applyReduction(reduction)
        } catch {
#if DEBUG
            assertionFailure("Failed to apply recovery intent: \(error)")
#endif
        }
    }

    private func applyQueueNeedsBuildMutation(_ value: Bool) {
        do {
            let reduction = try reduce(.setQueueNeedsBuild(value))
            guard !reduction.wasNoOp else { return }
            applyReduction(reduction)
        } catch {
            preconditionFailure("Failed to reduce queueNeedsBuild mutation: \(error)")
        }
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

    private func makeDomainInvariantSnapshot() -> DomainInvariantSnapshot {
        let poolIds = queueState.songPool.map(\.id)
        let queueIds = queueState.queueOrder.map(\.id)
        let poolIdSet = Set(poolIds)
        let queueIdSet = Set(queueIds)
        let queueParityExpected = !queueNeedsBuild && (queueState.hasQueue || playbackState.isActive)
        let playbackCurrentSongId = playbackState.currentSongId
        let reasons = domainInvariantReasons(
            poolIds: poolIds,
            queueIds: queueIds,
            poolIdSet: poolIdSet,
            queueIdSet: queueIdSet,
            queueParityExpected: queueParityExpected,
            playbackCurrentSongId: playbackCurrentSongId
        )
        return DomainInvariantSnapshot(
            poolIds: poolIds,
            queueIds: queueIds,
            poolIdSet: poolIdSet,
            queueIdSet: queueIdSet,
            queueParityExpected: queueParityExpected,
            playbackCurrentSongId: playbackCurrentSongId,
            reasons: reasons
        )
    }

    private func evaluateDomainInvariants() -> (isHealthy: Bool, reasons: [String]) {
        let snapshot = makeDomainInvariantSnapshot()
        return (isHealthy: snapshot.isHealthy, reasons: snapshot.reasons)
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
        let snapshot = makeDomainInvariantSnapshot()

        let queueHasUniqueIDs = !queueState.hasQueue || snapshot.queueIds.count == snapshot.queueIdSet.count
        let poolAndQueueMembershipMatch = !snapshot.queueParityExpected || snapshot.poolIdSet == snapshot.queueIdSet
        let transportSnapshot = refreshTransportSnapshot()
        let transportEntryCount = transportSnapshot.entryCount
        let transportCurrentSongId = transportSnapshot.currentSongId
        let transportEntryCountMatchesQueue = !snapshot.queueParityExpected || transportEntryCount == snapshot.queueIds.count
        let transportCurrentMatchesDomain =
            !snapshot.queueParityExpected ||
            transportCurrentSongId == queueState.currentSongId ||
            snapshot.playbackCurrentSongId == queueState.currentSongId

        var reasons = snapshot.reasons
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
            playbackCurrentSongId: snapshot.playbackCurrentSongId,
            transportEntryCount: transportEntryCount,
            transportCurrentSongId: transportCurrentSongId,
            queueHasUniqueIDs: queueHasUniqueIDs,
            poolAndQueueMembershipMatch: poolAndQueueMembershipMatch,
            transportEntryCountMatchesQueue: transportEntryCountMatchesQueue,
            transportCurrentMatchesDomain: transportCurrentMatchesDomain
        )
    }

    private func recordOperation(_ operation: QueueOperationID, detail: String? = nil, refreshTransport: Bool = false) {
        if refreshTransport {
            _ = refreshTransportSnapshot()
        }
        let invariant = evaluateDomainInvariants()
        let transport = cachedTransportSnapshot
        let record = QueueOperationRecord(
            id: UUID(),
            timestamp: Date(),
            operation: operation.rawValue,
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
        operationJournalVersion &+= 1
    }

    func exportQueueDiagnosticsSnapshot(trigger: String = "manual-export", detail: String? = nil) -> String {
        let invariant = evaluateQueueInvariants()
        recordOperation(.snapshotExport, detail: [trigger, detail].compactMap { $0 }.joined(separator: " | "))
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

    // MARK: - Algorithm Change

    /// Called when shuffle algorithm changes. Views should call this via onChange(of: appSettings.shuffleAlgorithm).
    func reshuffleWithNewAlgorithm(_ algorithm: ShuffleAlgorithm) async {
        if case .swapping = boundarySwapState {} else { boundarySwapState = .idle }
        do {
            let reduction = try reduce(.reshuffleAlgorithm(algorithm))
            guard !reduction.wasNoOp else {
                recordOperation(.reshuffleAlgorithmSkip, detail: "no-op")
                return
            }

            let outcome = try await applyReductionWithTransport(
                reduction,
                source: "reshuffle-algorithm",
                rollbackPolicy: .full
            )
            guard case .applied = outcome else { return }

            if playbackState.isActive {
                if queueNeedsBuild {
                    rearmBoundarySwapIfNeeded(after: reduction)
                    recordOperation(.reshuffleAlgorithmDeferred, detail: algorithm.rawValue)
                } else {
                    recordOperation(.reshuffleAlgorithmSuccess, detail: algorithm.rawValue)
                }
            } else {
                recordOperation(.reshuffleAlgorithmInvalidated, detail: algorithm.rawValue)
            }
        } catch {
            recordOperation(.reshuffleAlgorithmFailed, detail: error.localizedDescription)
        }
    }

    // MARK: - Song Management

    private func applyActiveAddReductionWithRetry(
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
                recordOperation(
                    .activeAddSyncNonTransientFailed,
                    detail: "source=\(source), error=\(error.localizedDescription)"
                )
                failureReason = "non-transient"
            }
            recordOperation(degradedOperation, detail: "\(successDetail), reason=\(failureReason)")
        }
    }

    private func applyNonActiveAddReduction(
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

    private func reductionContainsQueueSyncCommand(_ reduction: QueueEngineReduction) -> Bool {
        reduction.transportCommands.contains { command in
            switch command {
            case .setQueue, .replaceQueue:
                return true
            default:
                return false
            }
        }
    }

    private func rearmBoundarySwapIfNeeded(after reduction: QueueEngineReduction) {
        guard queueNeedsBuild, playbackState.isPlaying else { return }
        guard !reductionContainsQueueSyncCommand(reduction) else { return }
        armBoundarySwap()
    }

    private struct NonActiveAddReductionContext {
        let source: String
        let actionDescription: String
        let successOperation: QueueOperationID
        let deferredOperation: QueueOperationID
        let failureOperation: QueueOperationID
    }

    func addSong(_ song: Song) async throws {
        do {
            let reduction = try reduce(.addSong(song))
            guard !reduction.wasNoOp else {
                recordOperation(.addSongSkip, detail: "duplicate id=\(song.id)")
                return
            }

            if !reduction.requiresActiveTransportSync {
                try await applyNonActiveAddReduction(
                    reduction,
                    context: NonActiveAddReductionContext(
                        source: "add-song",
                        actionDescription: "Couldn't add the song to the active queue",
                        successOperation: .addSongSuccess,
                        deferredOperation: .addSongDeferredRebuild,
                        failureOperation: .addSongFailed
                    ),
                    successDetail: "id=\(song.id)",
                    failureDetail: "transport-sync-failed id=\(song.id)"
                )
                rearmBoundarySwapIfNeeded(after: reduction)
                return
            }

            await applyActiveAddReductionWithRetry(
                reduction,
                source: "add-song",
                successOperation: .addSongSuccess,
                degradedOperation: .addSongSyncDegraded,
                successDetail: "id=\(song.id)"
            )
        } catch QueueEngineError.capacityReached {
            recordOperation(.addSongFailed, detail: "capacity-reached id=\(song.id)")
            throw ShufflePlayerError.capacityReached
        } catch {
            let message = reportTransportFailure(action: "Couldn't add the song to the active queue", error: error)
            recordOperation(.addSongFailed, detail: "unexpected id=\(song.id)")
            throw ShufflePlayerError.playbackFailed(message)
        }
    }

    /// Seeds songs into the pool only; active transport synchronization is deferred to explicit queue rebuild/play.
    func seedSongs(_ newSongs: [Song]) throws {
        do {
            let reduction = try reduce(.seedSongs(newSongs))
            guard !reduction.wasNoOp else { return }
            applyReduction(reduction)
            recordOperation(.addSongsSuccess, detail: "batch=\(newSongs.count)")
        } catch QueueEngineError.capacityReached {
            recordOperation(.addSongsFailed, detail: "capacity-reached batch=\(newSongs.count)")
            throw ShufflePlayerError.capacityReached
        } catch {
            recordOperation(.addSongsFailed, detail: "unexpected batch=\(newSongs.count)")
            throw ShufflePlayerError.playbackFailed(error.localizedDescription)
        }
    }

    /// Add songs and reshuffle queue if playing (interleaves new songs throughout upcoming queue)
    func addSongsWithQueueRebuild(_ newSongs: [Song], algorithm: ShuffleAlgorithm? = nil) async throws {
        do {
            let reduction = try reduce(.addSongsWithRebuild(newSongs, algorithm: algorithm))
            guard !reduction.wasNoOp else { return }

            if !reduction.requiresActiveTransportSync {
                try await applyNonActiveAddReduction(
                    reduction,
                    context: NonActiveAddReductionContext(
                        source: "add-songs-rebuild",
                        actionDescription: "Couldn't sync newly added songs to the active queue",
                        successOperation: .addSongsRebuildSuccess,
                        deferredOperation: .addSongsRebuildDeferred,
                        failureOperation: .addSongsRebuildFailed
                    ),
                    successDetail: "batch=\(newSongs.count)",
                    failureDetail: "transport-sync-failed"
                )
                rearmBoundarySwapIfNeeded(after: reduction)
                return
            }

            await applyActiveAddReductionWithRetry(
                reduction,
                source: "add-songs-rebuild",
                successOperation: .addSongsRebuildSuccess,
                degradedOperation: .addSongsRebuildSyncDegraded,
                successDetail: "batch=\(newSongs.count)"
            )
        } catch QueueEngineError.capacityReached {
            recordOperation(.addSongsRebuildFailed, detail: "capacity-reached batch=\(newSongs.count)")
            throw ShufflePlayerError.capacityReached
        } catch {
            let message = reportTransportFailure(action: "Couldn't sync newly added songs to the active queue", error: error)
            recordOperation(.addSongsRebuildFailed, detail: "unexpected")
            throw ShufflePlayerError.playbackFailed(message)
        }
    }

    func removeSong(id: String) async {
        if case .swapping = boundarySwapState {} else { boundarySwapState = .idle }
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
                rearmBoundarySwapIfNeeded(after: reduction)
                recordOperation(.removeSongSuccess, detail: "id=\(id)")
            } catch {
                _ = reportTransportFailure(action: "Couldn't remove the song from the active queue", error: error)
                recordOperation(.removeSongFailed, detail: "id=\(id)")
            }
        } catch {
            _ = reportTransportFailure(action: "Couldn't remove the song from the active queue", error: error)
            recordOperation(.removeSongFailed, detail: "id=\(id), unexpected")
        }
    }

    func removeAllSongs() async {
        if case .swapping = boundarySwapState {} else { boundarySwapState = .idle }
        cancelActiveAddResyncRetry()
        do {
            let reduction = try reduce(.removeAllSongs)
            guard !reduction.wasNoOp else { return }

            do {
                let outcome = try await applyReductionWithTransport(
                    reduction,
                    source: "remove-all-songs",
                    rollbackPolicy: .none,
                    staleRollbackPolicy: .none,
                    afterApply: { self.playbackObserver.clearLastObservedSongId() }
                )
                switch outcome {
                case .applied:
                    recordOperation(.removeAllSongs)
                case .stale:
                    await musicService.pause()
                    applyQueueNeedsBuildMutation(false)
                    _ = refreshTransportSnapshot()
                    operationNotice = "Queue changed while clearing. Playback paused and queue cleared."
                    recordOperation(.removeAllSongsStaleForcePause, refreshTransport: true)
                    return
                }
            } catch {
                _ = reportTransportFailure(action: "Couldn't clear the active queue", error: error)
                recordOperation(.removeAllSongsFailed, detail: error.localizedDescription)
            }
        } catch {
            _ = reportTransportFailure(action: "Couldn't clear the active queue", error: error)
            recordOperation(.removeAllSongsFailed, detail: error.localizedDescription)
        }
    }

    func containsSong(id: String) -> Bool {
        queueState.containsSong(id: id)
    }

    // MARK: - Queue Preparation

    func prepareQueue(algorithm: ShuffleAlgorithm? = nil) async throws {
        let reduction = try reduce(.prepareQueue(algorithm: algorithm))
        guard !reduction.wasNoOp else {
            recordOperation(.prepareQueueSkip, detail: "empty-pool")
            return
        }

        let outcome = try await applyReductionWithTransport(
            reduction,
            source: "prepare-queue",
            rollbackPolicy: .full
        )
        switch outcome {
        case .applied:
            recordOperation(.prepareQueueSuccess, detail: queueState.algorithm.rawValue)
        case .stale:
            throw ShufflePlayerError.playbackFailed("Queue changed while syncing. Try again.")
        }
    }

    // MARK: - Playback Control

    func play(algorithm: ShuffleAlgorithm? = nil) async throws {
        if case .swapping = boundarySwapState {} else { boundarySwapState = .idle }
        let reduction = try reduce(.play(algorithm: algorithm))
        guard !reduction.wasNoOp else {
            recordOperation(.playSkip, detail: "empty-pool")
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
            recordOperation(.playSuccess)
        case .stale:
            throw ShufflePlayerError.playbackFailed("Queue changed while syncing. Tap play again.")
        }
    }

    func pause() async {
        if case .swapping = boundarySwapState {} else { boundarySwapState = .idle }
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
        recordOperation(.pause)
    }

    func skipToNext() async throws {
        if case .armed = boundarySwapState { boundarySwapState = .pendingSkip }
        let reduction = try reduce(.skipToNext)
        let outcome = try await applyReductionWithTransport(
            reduction,
            source: "skip-next",
            rollbackPolicy: .none
        )
        if case .stale = outcome {
            throw ShufflePlayerError.playbackFailed("Queue changed while syncing. Try skipping again.")
        }
        recordOperation(.skipNext)
    }

    func skipToPrevious() async throws {
        if case .armed = boundarySwapState { boundarySwapState = .pendingSkip }
        let reduction = try reduce(.skipToPrevious)
        let outcome = try await applyReductionWithTransport(
            reduction,
            source: "skip-previous",
            rollbackPolicy: .none
        )
        if case .stale = outcome {
            throw ShufflePlayerError.playbackFailed("Queue changed while syncing. Try skipping again.")
        }
        recordOperation(.skipPrevious)
    }

    func restartOrSkipToPrevious() async throws {
        if case .armed = boundarySwapState { boundarySwapState = .pendingSkip }
        let reduction = try reduce(.restartOrSkipToPrevious)
        let outcome = try await applyReductionWithTransport(
            reduction,
            source: "restart-or-skip-previous",
            rollbackPolicy: .none
        )
        if case .stale = outcome {
            throw ShufflePlayerError.playbackFailed("Queue changed while syncing. Try again.")
        }
        recordOperation(.restartOrSkipPrevious)
    }

    func togglePlayback(algorithm: ShuffleAlgorithm? = nil) async throws {
        if case .swapping = boundarySwapState {} else { boundarySwapState = .idle }
        let reduction = try reduce(.togglePlayback(algorithm: algorithm))
        guard !reduction.wasNoOp else {
            recordOperation(.togglePlaybackSkip, detail: "no-op")
            return
        }

        let outcome = try await applyReductionWithTransport(
            reduction,
            source: "toggle-playback",
            rollbackPolicy: .full
        )
        switch outcome {
        case .applied:
            recordOperation(.togglePlayback)
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
            recordOperation(.restoreSessionFailed)
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
            recordOperation(.restoreSessionFailed, detail: "reducer=\(error.localizedDescription)")
            return false
        }
        playbackObserver.setLastObservedSongId(result.lastObservedSongId)
        if let seek = result.pendingRestoreSeek {
            playbackObserver.setPendingRestoreSeek(songId: seek.songId, position: seek.position)
        }
        recordOperation(.restoreSessionSuccess)
        return true
    }

}
