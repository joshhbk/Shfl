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

    // Keeps each column to one direction, so clicking its header again doesn't flip it.
    static func oneWay(_ sortOrder: [KeyPathComparator<Song>]) -> [KeyPathComparator<Song>] {
        option(for: sortOrder).map { Self.sortOrder(for: $0) } ?? []
    }
}
