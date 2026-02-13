import Foundation

enum ShufflePlayerError: Error, Equatable {
    case capacityReached
    case notAuthorized
    case playbackFailed(String)
}

extension ShufflePlayerError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .capacityReached:
            return "Song limit reached."
        case .notAuthorized:
            return "Apple Music authorization is required."
        case .playbackFailed(let message):
            return message
        }
    }
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
    let transportEntryCount: Int?
    let transportCurrentSongId: String?
    let transportParityMismatch: Bool
}

struct QueueDriftTelemetry: Equatable, Sendable {
    var detections: Int = 0
    var reconciliations: Int = 0
    var unrepairedDetections: Int = 0
    var detectionsByTrigger: [String: Int] = [:]
    var detectionsByReason: [QueueDriftReason: Int] = [:]
    var recentEvents: [QueueDriftEvent] = []
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

struct QueueOperationJournal: Equatable, Sendable {
    static let maxRecords = 250

    var records: [QueueOperationRecord] = []

    mutating func append(_ record: QueueOperationRecord) {
        records.insert(record, at: 0)
        if records.count > Self.maxRecords {
            records.removeLast(records.count - Self.maxRecords)
        }
    }
}

struct QueueDriftEventSnapshot: Equatable, Sendable, Codable {
    let timestamp: Date
    let trigger: String
    let reasons: [String]
    let poolCount: Int
    let queueCount: Int
    let duplicateCount: Int
    let missingFromQueueCount: Int
    let missingFromPoolCount: Int
    let currentSongId: String?
    let preferredCurrentSongId: String?
    let repaired: Bool
    let transportEntryCount: Int?
    let transportCurrentSongId: String?
    let transportParityMismatch: Bool
}

struct QueueDriftTelemetrySnapshot: Equatable, Sendable, Codable {
    let detections: Int
    let reconciliations: Int
    let unrepairedDetections: Int
    let detectionsByTrigger: [String: Int]
    let detectionsByReason: [String: Int]
    let recentEvents: [QueueDriftEventSnapshot]

    init(_ telemetry: QueueDriftTelemetry) {
        detections = telemetry.detections
        reconciliations = telemetry.reconciliations
        unrepairedDetections = telemetry.unrepairedDetections
        detectionsByTrigger = telemetry.detectionsByTrigger
        detectionsByReason = Dictionary(
            uniqueKeysWithValues: telemetry.detectionsByReason.map { ($0.key.rawValue, $0.value) }
        )
        recentEvents = telemetry.recentEvents.map {
            QueueDriftEventSnapshot(
                timestamp: $0.timestamp,
                trigger: $0.trigger,
                reasons: $0.reasons.map(\.rawValue),
                poolCount: $0.poolCount,
                queueCount: $0.queueCount,
                duplicateCount: $0.duplicateCount,
                missingFromQueueCount: $0.missingFromQueueCount,
                missingFromPoolCount: $0.missingFromPoolCount,
                currentSongId: $0.currentSongId,
                preferredCurrentSongId: $0.preferredCurrentSongId,
                repaired: $0.repaired,
                transportEntryCount: $0.transportEntryCount,
                transportCurrentSongId: $0.transportCurrentSongId,
                transportParityMismatch: $0.transportParityMismatch
            )
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
    let driftTelemetry: QueueDriftTelemetrySnapshot
    let operationJournal: [QueueOperationRecord]
}
