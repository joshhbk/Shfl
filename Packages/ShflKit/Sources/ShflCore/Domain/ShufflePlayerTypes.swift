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
