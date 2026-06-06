import XCTest
@testable import Shfl

// MARK: - Test Helper

/// Holds the state that backs the closures passed to `QueueTransportSync`.
@MainActor
final class QueueTransportSyncTestHarness {
    var queueState: QueueState = .empty
    var playbackState: PlaybackState = .empty
    var queueRevision: Int = 0
    var queueNeedsBuild: Bool = false
    var operationNotice: String?
    var applyReductionCallCount = 0
    var restoreEngineStateCallCount = 0
    var applyRecoveryIntentCallCount = 0
    var lastRecoveryIntent: QueueIntent?
    var lastObservedSongId: String?

    let mockService: MockMusicService
    lazy var sync: QueueTransportSync = {
        QueueTransportSync(
            musicService: mockService,
            readQueueRevision: { self.queueRevision },
            readEngineState: {
                QueueEngineState(queueState: self.queueState, playbackState: self.playbackState, revision: self.queueRevision, queueNeedsBuild: self.queueNeedsBuild)
            },
            applyReduction: { reduction in
                self.applyReductionCallCount += 1
                self.queueState = reduction.nextState.queueState
                self.playbackState = reduction.nextState.playbackState
                self.queueRevision = reduction.nextState.revision
                self.queueNeedsBuild = reduction.nextState.queueNeedsBuild
            },
            restoreEngineState: { state in
                self.restoreEngineStateCallCount += 1
                self.queueState = state.queueState
                self.playbackState = state.playbackState
                self.queueRevision = state.revision
                self.queueNeedsBuild = state.queueNeedsBuild
            },
            applyRecoveryIntent: { intent in
                self.applyRecoveryIntentCallCount += 1
                self.lastRecoveryIntent = intent
            },
            setOperationNotice: { message in
                self.operationNotice = message
            },
            setLastObservedSongId: { id in
                self.lastObservedSongId = id
            },
            clearLastObservedSongId: {
                self.lastObservedSongId = nil
            },
            applyQueueNeedsBuildMutation: { value in
                self.queueNeedsBuild = value
            }
        )
    }()

    init(mockService: MockMusicService = MockMusicService()) {
        self.mockService = mockService
    }

    var engineState: QueueEngineState {
        QueueEngineState(queueState: queueState, playbackState: playbackState, revision: queueRevision, queueNeedsBuild: queueNeedsBuild)
    }
}

// MARK: - Tests

@MainActor
final class QueueTransportSyncTests: XCTestCase {
    private let songA = Song(id: "a", title: "A", artist: "Artist", albumTitle: "Album", artworkURL: nil)
    private let songB = Song(id: "b", title: "B", artist: "Artist", albumTitle: "Album", artworkURL: nil)
    private let songC = Song(id: "c", title: "C", artist: "Artist", albumTitle: "Album", artworkURL: nil)
    private var songs: [Song] { [songA, songB, songC] }

    // MARK: - Core Transport Sync

    func testApplyReductionWithTransport_appliesStateAndExecutesCommands() async throws {
        let harness = QueueTransportSyncTestHarness()
        harness.queueState = QueueState(songPool: songs, queueOrder: songs, currentIndex: 0)

        let reduction = try QueueEngineReducer.reduce(state: harness.engineState, intent: .prepareQueue(algorithm: nil))

        let outcome = try await harness.sync.applyReductionWithTransport(reduction, source: "test")

        XCTAssertEqual(outcome, TransportApplyOutcome.applied)
        XCTAssertEqual(harness.applyReductionCallCount, 1)
        XCTAssertFalse(harness.queueNeedsBuild)
        XCTAssertTrue(harness.queueState.hasQueue)
    }

    func testApplyReductionWithTransport_returnsStaleOnRevisionMismatch() async throws {
        let harness = QueueTransportSyncTestHarness()
        harness.queueState = QueueState(songPool: songs, queueOrder: songs, currentIndex: 0)
        harness.queueRevision = 5

        let staleCommand = TransportCommand.pause(revision: 3)
        let staleReduction = QueueEngineReduction(nextState: harness.engineState, transportCommands: [staleCommand], wasNoOp: false)

        let outcome = try await harness.sync.applyReductionWithTransport(staleReduction, source: "test-stale")

        XCTAssertEqual(outcome, TransportApplyOutcome.stale)
        XCTAssertEqual(harness.applyRecoveryIntentCallCount, 1)
        XCTAssertNotNil(harness.lastRecoveryIntent)
    }

    func testApplyReductionWithTransport_revisionMatchSucceeds() async throws {
        let harness = QueueTransportSyncTestHarness()
        harness.queueState = QueueState(songPool: songs, queueOrder: songs, currentIndex: 0)
        harness.queueRevision = 5

        let command = TransportCommand.pause(revision: 5)
        let reduction = QueueEngineReduction(nextState: harness.engineState, transportCommands: [command], wasNoOp: false)

        let outcome = try await harness.sync.applyReductionWithTransport(reduction, source: "test-match")

        XCTAssertEqual(outcome, TransportApplyOutcome.applied)
    }

    func testApplyReductionWithTransport_rollsBackOnExecFailure() async throws {
        let harness = QueueTransportSyncTestHarness()
        harness.queueState = QueueState(songPool: songs, queueOrder: [songA, songB])
        harness.playbackState = PlaybackState.playing(songA)
        let preState = harness.engineState

        await harness.mockService.setShouldThrowOnPlay(TestError.transportFailed)

        let reduction = try QueueEngineReducer.reduce(state: harness.engineState, intent: .play(algorithm: nil))

        do {
            _ = try await harness.sync.applyReductionWithTransport(reduction, source: "test-rollback", rollbackPolicy: RollbackPolicy.full)
            XCTFail("Expected throw")
        } catch {
            XCTAssertEqual(harness.queueState.queueOrder, preState.queueState.queueOrder)
            XCTAssertEqual(harness.queueRevision, preState.revision)
        }
    }

    // MARK: - Stale Detection

    func testReportTransportFailure_setsNoticeOnOfflineError() {
        let harness = QueueTransportSyncTestHarness()
        let offlineError = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)

        let message = harness.sync.reportTransportFailure(action: "Test action", error: offlineError)

        XCTAssertTrue(message.contains("offline"))
        XCTAssertNotNil(harness.operationNotice)
        XCTAssertTrue(harness.operationNotice?.contains("offline") ?? false)
    }

    func testReportTransportFailure_genericMessageOnOtherError() {
        let harness = QueueTransportSyncTestHarness()
        let error = NSError(domain: "test", code: 42)

        let message = harness.sync.reportTransportFailure(action: "Test action", error: error)

        XCTAssertFalse(message.contains("offline"))
        XCTAssertNotNil(harness.operationNotice)
    }

    // MARK: - Boundary Swap

    func testInterceptResolution_doesNotInterceptWhenIdle() {
        let harness = QueueTransportSyncTestHarness()
        let resolution = PlaybackStateResolution(resolvedState: .stopped, resolvedSongId: nil, shouldUpdateCurrentSong: false, songIdToMarkPlayed: songA.id, shouldClearHistory: true)

        let result = harness.sync.interceptResolution(resolution)

        XCTAssertFalse(result)
    }

    func testResetOnUserAction_isSafe() {
        let harness = QueueTransportSyncTestHarness()
        harness.sync.resetOnUserAction()
    }

    func testSetPendingSkip_isSafe() {
        let harness = QueueTransportSyncTestHarness()
        harness.sync.setPendingSkip()
    }

    func testRearmBoundarySwapIfNeeded_whenPlayingAndQueueNeedsBuild() {
        let harness = QueueTransportSyncTestHarness()
        harness.queueState = QueueState(songPool: songs, queueOrder: songs, currentIndex: 0)
        harness.playbackState = PlaybackState.playing(songA)
        harness.queueNeedsBuild = true

        let noOpReduction = QueueEngineReduction(nextState: harness.engineState, transportCommands: [], wasNoOp: true)
        harness.sync.rearmBoundarySwapIfNeeded(after: noOpReduction)
    }

    func testRearmBoundarySwapIfNeeded_skipsWhenNotPlaying() {
        let harness = QueueTransportSyncTestHarness()
        harness.queueState = QueueState(songPool: songs, queueOrder: songs, currentIndex: 0)
        harness.playbackState = PlaybackState.paused(songA)
        harness.queueNeedsBuild = true

        let reduction = QueueEngineReduction(nextState: harness.engineState, transportCommands: [], wasNoOp: true)
        harness.sync.rearmBoundarySwapIfNeeded(after: reduction)
    }

    func testCancelBoundarySwapPolling_isSafeWhenIdle() {
        let harness = QueueTransportSyncTestHarness()
        harness.sync.cancelBoundarySwapPolling()
    }

    // MARK: - Active-Add Retry

    func testCancelActiveAddResyncRetry_isSafeWhenIdle() {
        let harness = QueueTransportSyncTestHarness()
        harness.sync.cancelActiveAddResyncRetry()
    }

    func testApplyActiveAddReductionWithRetry_appliedOutcome() async {
        let harness = QueueTransportSyncTestHarness()
        harness.queueState = QueueState(songPool: songs, queueOrder: songs, currentIndex: 0)

        let noOpReduction = QueueEngineReduction(nextState: harness.engineState, transportCommands: [], wasNoOp: true)
        await harness.sync.applyActiveAddReductionWithRetry(noOpReduction, source: "test", successOperation: .addSongSuccess, degradedOperation: .addSongSyncDegraded, successDetail: "test-detail")
    }

    func testApplyActiveAddReductionWithRetry_staleTriggersRetry() async {
        let harness = QueueTransportSyncTestHarness()
        harness.queueState = QueueState(songPool: songs, queueOrder: songs, currentIndex: 0)
        harness.queueRevision = 5

        let staleCommand = TransportCommand.pause(revision: 3)
        let staleReduction = QueueEngineReduction(nextState: harness.engineState, transportCommands: [staleCommand], wasNoOp: false)

        await harness.sync.applyActiveAddReductionWithRetry(staleReduction, source: "test-stale", successOperation: .addSongSuccess, degradedOperation: .addSongSyncDegraded, successDetail: "test")
    }

    // MARK: - Non-Active Add

    func testApplyNonActiveAddReduction_appliedOutcome() async throws {
        let harness = QueueTransportSyncTestHarness()
        harness.queueState = QueueState(songPool: songs, queueOrder: songs, currentIndex: 0)

        let noOpReduction = QueueEngineReduction(nextState: harness.engineState, transportCommands: [], wasNoOp: true)
        let context = QueueTransportSync.NonActiveAddReductionContext(
            source: "test", actionDescription: "Test action",
            successOperation: .addSongSuccess, deferredOperation: .addSongDeferredRebuild, failureOperation: .addSongFailed
        )

        try await harness.sync.applyNonActiveAddReduction(noOpReduction, context: context, successDetail: "test-detail", failureDetail: "test-failure")
    }

    // MARK: - Diagnostics

    func testRecordOperation_incrementsVersion() {
        let harness = QueueTransportSyncTestHarness()
        let initialVersion = harness.sync.operationJournalVersion

        harness.sync.recordOperation(.playerInit)

        XCTAssertGreaterThan(harness.sync.operationJournalVersion, initialVersion)
    }

    func testRecentQueueOperations_returnsRecords() {
        let harness = QueueTransportSyncTestHarness()
        XCTAssertTrue(harness.sync.recentQueueOperations.isEmpty)

        harness.sync.recordOperation(.playerInit)
        harness.sync.recordOperation(.pause)

        let records = harness.sync.recentQueueOperations
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records[0].operation, "pause")
        XCTAssertEqual(records[1].operation, "player-init")
    }

    func testQueueInvariantCheck_reportsHealthyOnEmpty() {
        let harness = QueueTransportSyncTestHarness()
        let check = harness.sync.queueInvariantCheck
        XCTAssertTrue(check.isHealthy)
    }

    func testExportQueueDiagnosticsSnapshot_returnsJSON() {
        let harness = QueueTransportSyncTestHarness()
        harness.queueState = QueueState(songPool: songs, queueOrder: songs, currentIndex: 0)
        harness.playbackState = PlaybackState.playing(songA)

        let json = harness.sync.exportQueueDiagnosticsSnapshot(trigger: "test")

        XCTAssertTrue(json.hasPrefix("{"))
        XCTAssertTrue(json.contains("test"))
        XCTAssertNotNil(try? JSONSerialization.jsonObject(with: Data(json.utf8), options: []))
    }

    // MARK: - Invariant Enforcement

    func testEnforceDomainInvariants_healthyDoesNothing() {
        let harness = QueueTransportSyncTestHarness()
        harness.queueState = QueueState(songPool: songs, queueOrder: songs, currentIndex: 0)

        harness.sync.enforceDomainInvariants(context: "test")
        XCTAssertEqual(harness.applyRecoveryIntentCallCount, 0)
    }

    func testEnforceDomainInvariants_triggersRecoveryOnMismatch() {
        let harness = QueueTransportSyncTestHarness()
        harness.queueState = QueueState(songPool: songs, queueOrder: [songA, songB], currentIndex: 0)
        harness.playbackState = PlaybackState.playing(songA)
        harness.queueNeedsBuild = false

        harness.sync.enforceDomainInvariants(context: "test-mismatch")

        XCTAssertEqual(harness.applyRecoveryIntentCallCount, 1)
    }

    // MARK: - Rollback Policies

    func testRollbackPolicyFull_restoresStateOnTransportFailure() async throws {
        let harness = QueueTransportSyncTestHarness()
        harness.queueState = QueueState(songPool: songs, queueOrder: [songA, songB])
        harness.playbackState = PlaybackState.playing(songA)
        let preState = harness.engineState

        await harness.mockService.setShouldThrowOnPlay(TestError.transportFailed)

        let reduction = try QueueEngineReducer.reduce(state: harness.engineState, intent: .play(algorithm: nil))

        do {
            _ = try await harness.sync.applyReductionWithTransport(reduction, source: "test", rollbackPolicy: RollbackPolicy.full)
            XCTFail("Expected throw")
        } catch {
            XCTAssertEqual(harness.queueState.queueOrder, preState.queueState.queueOrder)
        }
    }

    func testRollbackPolicyNone_doesNotRestoreState() async throws {
        let harness = QueueTransportSyncTestHarness()
        harness.queueState = QueueState(songPool: songs, queueOrder: [songA, songB])
        harness.playbackState = PlaybackState.playing(songA)

        await harness.mockService.setShouldThrowOnPlay(TestError.transportFailed)

        let reduction = try QueueEngineReducer.reduce(state: harness.engineState, intent: .play(algorithm: nil))

        do {
            _ = try await harness.sync.applyReductionWithTransport(reduction, source: "test", rollbackPolicy: RollbackPolicy.none)
            XCTFail("Expected throw")
        } catch {
            // With .none rollback, state changes from the reduction remain applied
        }
    }
}

private enum TestError: Error {
    case transportFailed
}