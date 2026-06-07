import Foundation

@Observable
@MainActor
final class ShufflePlayer {
    @ObservationIgnored private let playbackTransport: PlaybackTransport
    @ObservationIgnored private let playbackObserver: PlaybackStateObserver
    @ObservationIgnored private lazy var transportSync = QueueTransportSync(
        playbackTransport: playbackTransport,
        readQueueRevision: { [weak self] in self?.queueRevision ?? 0 },
        readEngineState: { [weak self] in self?.engineState ?? QueueEngineState(queueState: .empty, playbackState: .empty, revision: 0, queueNeedsBuild: false) },
        applyReduction: { [weak self] reduction in self?.applyReduction(reduction) },
        restoreEngineState: { [weak self] state in self?.restoreEngineState(state) },
        applyRecoveryIntent: { [weak self] intent in self?.applyRecoveryIntent(intent) },
        setOperationNotice: { [weak self] message in self?.operationNotice = message },
        setLastObservedSongId: { [weak self] id in self?.playbackObserver.setLastObservedSongId(id) },
        clearLastObservedSongId: { [weak self] in self?.playbackObserver.clearLastObservedSongId() },
        applyQueueNeedsBuildMutation: { [weak self] value in self?.applyQueueNeedsBuildMutation(value) }
    )
    // (active-add retry state lives in QueueTransportSync)

    /// Single source of truth for queue state
    private(set) var queueState: QueueState = .empty

    /// Current playback state from MusicKit
    private(set) var playbackState: PlaybackState = .empty

    /// Monotonic revision used to gate stale transport commands.
    private(set) var queueRevision: Int = 0

    /// Whether playback should rebuild transport queue before attempting play.
    private(set) var queueNeedsBuild = true

    /// Rolling operation journal for queue diagnostics.
    /// Non-blocking operation notice for queue/transport sync failures.
    private(set) var operationNotice: String?

    // Retry orchestration state intentionally lives outside the reducer.
    // It controls when we reinvoke reducer intents, not domain queue semantics.
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
    var transportQueueEntryCount: Int { playbackTransport.transportQueueEntryCount }

    /// Debug: ID of the song currently selected in the MusicKit transport
    var transportCurrentSongId: String? { playbackTransport.currentSongId }

    /// Debug: recent queue operations (most recent first).
    var recentQueueOperations: [QueueOperationRecord] {
        transportSync.recentQueueOperations
    }

    /// Debug: latest invariant check over domain + transport queue state.
    var queueInvariantCheck: QueueInvariantCheck { transportSync.queueInvariantCheck }

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

    init(playbackTransport: PlaybackTransport) {
        self.playbackTransport = playbackTransport
        self.playbackObserver = PlaybackStateObserver(playbackTransport: playbackTransport)
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
        if transportSync.interceptResolution(resolution) { return }

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
        recordOperation(
            .playbackResolution,
            detail: "state=\(playbackStateLabel(resolution.resolvedState)), song=\(resolution.resolvedSongId ?? "nil")"
        )
    }

    func clearOperationNotice() {
        operationNotice = nil
        transportSync.recordOperation(.clearOperationNotice)
    }

    /// Debug-only escape hatch to return queue and diagnostics to a clean baseline.
    func hardResetQueueForDebug() async {
        transportSync.cancelActiveAddResyncRetry()
        transportSync.cancelBoundarySwapPolling()
        await removeAllSongs()
        transportSync.resetJournal()
        operationNotice = nil
        playbackObserver.clearLastObservedSongId()
        transportSync.recordOperation(.hardResetQueue)
    }

    // MARK: - Diagnostics

    /// Thin wrapper that forwards to the transport sync module.
    private func recordOperation(_ operation: QueueOperationID, detail: String? = nil, refreshTransport: Bool = false) {
        transportSync.recordOperation(operation, detail: detail, refreshTransport: refreshTransport)
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

    private func restoreEngineState(_ state: QueueEngineState) {
        queueState = state.queueState
        playbackState = state.playbackState
        queueRevision = state.revision
        queueNeedsBuild = state.queueNeedsBuild
    }

    private func enforceDomainInvariants(context: String) {
        transportSync.enforceDomainInvariants(context: context)
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













    func exportQueueDiagnosticsSnapshot(trigger: String = "manual-export", detail: String? = nil) -> String {
        transportSync.exportQueueDiagnosticsSnapshot(trigger: trigger, detail: detail)
    }

    // MARK: - Algorithm Change

    /// Called when shuffle algorithm changes. Views should call this via onChange(of: appSettings.shuffleAlgorithm).
    func reshuffleWithNewAlgorithm(_ algorithm: ShuffleAlgorithm) async {
        transportSync.resetOnUserAction()
        do {
            let reduction = try reduce(.reshuffleAlgorithm(algorithm))
            guard !reduction.wasNoOp else {
                recordOperation(.reshuffleAlgorithmSkip, detail: "no-op")
                return
            }

            let outcome = try await transportSync.applyReductionWithTransport(
                reduction,
                source: "reshuffle-algorithm",
                rollbackPolicy: .full
            )
            guard case .applied = outcome else { return }

            if playbackState.isActive {
                if queueNeedsBuild {
                    transportSync.rearmBoundarySwapIfNeeded(after: reduction)
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

    func addSong(_ song: Song) async throws {
        do {
            let reduction = try reduce(.addSong(song))
            guard !reduction.wasNoOp else {
                recordOperation(.addSongSkip, detail: "duplicate id=\(song.id)")
                return
            }

            if !reduction.requiresActiveTransportSync {
                try await transportSync.applyNonActiveAddReduction(
                    reduction,
                    context: QueueTransportSync.NonActiveAddReductionContext(
                        source: "add-song",
                        actionDescription: "Couldn't add the song to the active queue",
                        successOperation: .addSongSuccess,
                        deferredOperation: .addSongDeferredRebuild,
                        failureOperation: .addSongFailed
                    ),
                    successDetail: "id=\(song.id)",
                    failureDetail: "transport-sync-failed id=\(song.id)"
                )
                transportSync.rearmBoundarySwapIfNeeded(after: reduction)
                return
            }

            await transportSync.applyActiveAddReductionWithRetry(
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
            let message = transportSync.reportTransportFailure(action: "Couldn't add the song to the active queue", error: error)
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
                try await transportSync.applyNonActiveAddReduction(
                    reduction,
                    context: QueueTransportSync.NonActiveAddReductionContext(
                        source: "add-songs-rebuild",
                        actionDescription: "Couldn't sync newly added songs to the active queue",
                        successOperation: .addSongsRebuildSuccess,
                        deferredOperation: .addSongsRebuildDeferred,
                        failureOperation: .addSongsRebuildFailed
                    ),
                    successDetail: "batch=\(newSongs.count)",
                    failureDetail: "transport-sync-failed"
                )
                transportSync.rearmBoundarySwapIfNeeded(after: reduction)
                return
            }

            await transportSync.applyActiveAddReductionWithRetry(
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
            let message = transportSync.reportTransportFailure(action: "Couldn't sync newly added songs to the active queue", error: error)
            recordOperation(.addSongsRebuildFailed, detail: "unexpected")
            throw ShufflePlayerError.playbackFailed(message)
        }
    }

    func removeSong(id: String) async {
        transportSync.resetOnUserAction()
        do {
            let reduction = try reduce(.removeSong(id: id))
            guard !reduction.wasNoOp else { return }

            do {
                let outcome = try await transportSync.applyReductionWithTransport(
                    reduction,
                    source: "remove-song",
                    rollbackPolicy: .full
                )
                guard case .applied = outcome else { return }
                transportSync.rearmBoundarySwapIfNeeded(after: reduction)
                recordOperation(.removeSongSuccess, detail: "id=\(id)")
            } catch {
                _ = transportSync.reportTransportFailure(action: "Couldn't remove the song from the active queue", error: error)
                recordOperation(.removeSongFailed, detail: "id=\(id)")
            }
        } catch {
            _ = transportSync.reportTransportFailure(action: "Couldn't remove the song from the active queue", error: error)
            recordOperation(.removeSongFailed, detail: "id=\(id), unexpected")
        }
    }

    func removeAllSongs() async {
        transportSync.resetOnUserAction()
        transportSync.cancelActiveAddResyncRetry()
        do {
            let reduction = try reduce(.removeAllSongs)
            guard !reduction.wasNoOp else { return }

            do {
                let outcome = try await transportSync.applyReductionWithTransport(
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
                    await playbackTransport.pause()
                    applyQueueNeedsBuildMutation(false)
                    _ = transportSync.refreshTransportSnapshot()
                    operationNotice = "Queue changed while clearing. Playback paused and queue cleared."
                    recordOperation(.removeAllSongsStaleForcePause, refreshTransport: true)
                    return
                }
            } catch {
                _ = transportSync.reportTransportFailure(action: "Couldn't clear the active queue", error: error)
                recordOperation(.removeAllSongsFailed, detail: error.localizedDescription)
            }
        } catch {
            _ = transportSync.reportTransportFailure(action: "Couldn't clear the active queue", error: error)
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

        let outcome = try await transportSync.applyReductionWithTransport(
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
        transportSync.resetOnUserAction()
        let reduction = try reduce(.play(algorithm: algorithm))
        guard !reduction.wasNoOp else {
            recordOperation(.playSkip, detail: "empty-pool")
            return
        }

        let outcome = try await transportSync.applyReductionWithTransport(
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
        transportSync.resetOnUserAction()
        guard let reduction = try? reduce(.pause) else { return }
        do {
            let outcome = try await transportSync.applyReductionWithTransport(
                reduction,
                source: "pause",
                rollbackPolicy: .none
            )
            if case .stale = outcome {
                return
            }
        } catch {
            _ = transportSync.reportTransportFailure(action: "Couldn't pause playback", error: error)
        }
        recordOperation(.pause)
    }

    func skipToNext() async throws {
        transportSync.setPendingSkip()
        let reduction = try reduce(.skipToNext)
        let outcome = try await transportSync.applyReductionWithTransport(
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
        transportSync.setPendingSkip()
        let reduction = try reduce(.skipToPrevious)
        let outcome = try await transportSync.applyReductionWithTransport(
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
        transportSync.setPendingSkip()
        let reduction = try reduce(.restartOrSkipToPrevious)
        let outcome = try await transportSync.applyReductionWithTransport(
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
        transportSync.resetOnUserAction()
        let reduction = try reduce(.togglePlayback(algorithm: algorithm))
        guard !reduction.wasNoOp else {
            recordOperation(.togglePlaybackSkip, detail: "no-op")
            return
        }

        let outcome = try await transportSync.applyReductionWithTransport(
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
        playbackObserver.beginSuppressingHistory()
        defer { playbackObserver.endSuppressingHistory() }

        let restorer = SessionRestorer(playbackTransport: playbackTransport)
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
        recordOperation(.restoreSessionSuccess)
        return true
    }

}
