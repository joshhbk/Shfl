import Foundation

enum ShufflePlayerError: Error, Equatable {
    case capacityReached
    case playbackFailed(String)
}

extension ShufflePlayerError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .capacityReached:
            return "Song limit reached."
        case .playbackFailed(let message):
            return message
        }
    }
}

struct QueueInvariantCheck: Equatable, Sendable, Codable {
    let isHealthy: Bool
    let reasons: [String]
    let poolCount: Int
    let queueCount: Int
    let playedCount: Int
    let currentIndex: Int
    let domainCurrentSongId: String?
    let playbackCurrentSongId: String?
    let transportEntryCount: Int
    let transportCurrentSongId: String?
    let queueHasUniqueIDs: Bool
    let poolAndQueueMembershipMatch: Bool
    let transportEntryCountMatchesQueue: Bool
    let transportCurrentMatchesDomain: Bool
}

struct QueueOperationRecord: Equatable, Sendable, Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let operation: String
    let detail: String?
    let playbackState: String
    let poolCount: Int
    let queueCount: Int
    let currentSongId: String?
    let transportEntryCount: Int
    let transportCurrentSongId: String?
    let invariantHealthy: Bool
    let invariantReasons: [String]
}

enum QueueOperationID: String, Sendable {
    case playerInit = "player-init"
    case playbackResolution = "playback-resolution"
    case playbackResolutionIllegalTransport = "playback-resolution-illegal-transport"
    case playbackResolutionReducerFailed = "playback-resolution-reducer-failed"
    case clearOperationNotice = "clear-operation-notice"
    case hardResetQueue = "hard-reset-queue"
    case transportFailure = "transport-failure"
    case transportCommandStale = "transport-command-stale"
    case invariantViolation = "invariant-violation"
    case snapshotExport = "snapshot-export"
    case snapshotExportFailed = "snapshot-export-failed"
    case reshuffleAlgorithmSkip = "reshuffle-algorithm-skip"
    case reshuffleAlgorithmDeferred = "reshuffle-algorithm-deferred"
    case reshuffleAlgorithmSuccess = "reshuffle-algorithm-success"
    case reshuffleAlgorithmInvalidated = "reshuffle-algorithm-invalidated"
    case reshuffleAlgorithmFailed = "reshuffle-algorithm-failed"
    case addSongSkip = "add-song-skip"
    case addSongFailed = "add-song-failed"
    case addSongSuccess = "add-song-success"
    case addSongDeferredRebuild = "add-song-deferred-rebuild"
    case addSongSyncDegraded = "add-song-sync-degraded"
    case addSongsSuccess = "add-songs-success"
    case addSongsFailed = "add-songs-failed"
    case addSongsRebuildFailed = "add-songs-rebuild-failed"
    case addSongsRebuildSuccess = "add-songs-rebuild-success"
    case addSongsRebuildDeferred = "add-songs-rebuild-deferred"
    case addSongsRebuildSyncDegraded = "add-songs-rebuild-sync-degraded"
    case removeSongSuccess = "remove-song-success"
    case removeSongFailed = "remove-song-failed"
    case removeAllSongs = "remove-all-songs"
    case removeAllSongsStaleForcePause = "remove-all-songs-stale-force-pause"
    case removeAllSongsFailed = "remove-all-songs-failed"
    case prepareQueueSkip = "prepare-queue-skip"
    case prepareQueueSuccess = "prepare-queue-success"
    case playSkip = "play-skip"
    case playSuccess = "play-success"
    case pause = "pause"
    case skipNext = "skip-next"
    case skipPrevious = "skip-previous"
    case restartOrSkipPrevious = "restart-or-skip-previous"
    case togglePlayback = "toggle-playback"
    case togglePlaybackSkip = "toggle-playback-skip"
    case restoreSessionSuccess = "restore-session-success"
    case restoreSessionFailed = "restore-session-failed"
    case activeAddSyncRetryScheduled = "active-add-sync-retry-scheduled"
    case activeAddSyncRetryAttempt = "active-add-sync-retry-attempt"
    case activeAddSyncRetrySuccess = "active-add-sync-retry-success"
    case activeAddSyncRetryExhausted = "active-add-sync-retry-exhausted"
    case activeAddSyncNonTransientFailed = "active-add-sync-nontransient-failed"
    case boundarySyncStarted = "boundary-sync-started"
    case deferredTransportRebuilt = "deferred-transport-rebuilt"
}

struct QueueOperationJournal: Equatable, Sendable {
    static let maxRecords = 250

    private var storage: [QueueOperationRecord?] = Array(repeating: nil, count: Self.maxRecords)
    private var writeIndex = 0
    private var recordCount = 0

    var records: [QueueOperationRecord] {
        guard recordCount > 0 else { return [] }

        var newestFirst: [QueueOperationRecord] = []
        newestFirst.reserveCapacity(recordCount)

        for offset in 0..<recordCount {
            let index = (writeIndex - 1 - offset + Self.maxRecords) % Self.maxRecords
            if let record = storage[index] {
                newestFirst.append(record)
            }
        }

        return newestFirst
    }

    mutating func append(_ record: QueueOperationRecord) {
        storage[writeIndex] = record
        writeIndex = (writeIndex + 1) % Self.maxRecords
        if recordCount < Self.maxRecords {
            recordCount += 1
        }
    }
}

struct QueueDiagnosticsSnapshot: Equatable, Sendable, Codable {
    let exportedAt: Date
    let trigger: String
    let detail: String?
    let playbackState: String
    let poolSongIds: [String]
    let queueSongIds: [String]
    let playedSongIds: [String]
    let currentIndex: Int
    let currentSongId: String?
    let transportEntryCount: Int
    let transportCurrentSongId: String?
    let invariantCheck: QueueInvariantCheck
    let operationJournal: [QueueOperationRecord]
}
