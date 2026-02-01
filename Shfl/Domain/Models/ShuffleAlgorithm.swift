import Foundation

enum ShuffleAlgorithm: String, CaseIterable, Sendable, Hashable {
    case pureRandom = "pureRandom"
    case noRepeat = "noRepeat"
    case weightedByRecency = "weightedByRecency"
    case weightedByPlayCount = "weightedByPlayCount"
    case artistSpacing = "artistSpacing"

    var displayName: String {
        switch self {
        case .pureRandom: return "Pure Random"
        case .noRepeat: return "Full Shuffle"
        case .weightedByRecency: return "Least Recent"
        case .weightedByPlayCount: return "Least Played"
        case .artistSpacing: return "Artist Spacing"
        }
    }

    var description: String {
        switch self {
        case .pureRandom:
            return "Picks songs randomly. The same song may play again before others."
        case .noRepeat:
            return "Shuffles your queue and plays every song before repeating."
        case .weightedByRecency:
            return "Prioritizes songs you haven't listened to recently."
        case .weightedByPlayCount:
            return "Prioritizes songs with fewer plays."
        case .artistSpacing:
            return "Shuffles while avoiding back-to-back songs from the same artist."
        }
    }

    /// SF Symbol name for Dynamic Island display
    var iconName: String {
        switch self {
        case .pureRandom: return "dice"
        case .noRepeat: return "arrow.triangle.2.circlepath"
        case .weightedByRecency: return "clock.arrow.circlepath"
        case .weightedByPlayCount: return "chart.bar.fill"
        case .artistSpacing: return "person.2.wave.2"
        }
    }
}
