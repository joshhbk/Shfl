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
