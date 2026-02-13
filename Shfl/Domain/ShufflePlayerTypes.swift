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
