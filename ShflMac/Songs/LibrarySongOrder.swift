import Foundation
import ShflCore

enum LibrarySongOrder {
    static func sortOrder(for option: SortOption) -> [KeyPathComparator<Song>] {
        switch option {
        case .alphabetical: [KeyPathComparator(\Song.title)]
        case .mostPlayed: [KeyPathComparator(\Song.playCount, order: .reverse)]
        case .recentlyPlayed, .recentlyAdded: []
        }
    }

    static func option(for sortOrder: [KeyPathComparator<Song>]) -> SortOption? {
        switch sortOrder.first?.keyPath {
        case \Song.title: .alphabetical
        case \Song.playCount: .mostPlayed
        default: nil
        }
    }
}
