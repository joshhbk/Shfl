import Foundation
import ShflCore

/// Sorts songs that are all loaded, like an artist's, the way the catalog sorts the library.
enum SongOrder {
    static func sorted(_ songs: [Song], by order: SortOption) -> [Song] {
        songs.sorted { lhs, rhs in
            switch order {
            case .alphabetical:
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            case .mostPlayed:
                return lhs.playCount != rhs.playCount ? lhs.playCount > rhs.playCount : byTitle(lhs, rhs)
            case .recentlyPlayed:
                return newerFirst(lhs.lastPlayedDate, rhs.lastPlayedDate) ?? byTitle(lhs, rhs)
            case .recentlyAdded:
                return newerFirst(lhs.dateAdded, rhs.dateAdded) ?? byTitle(lhs, rhs)
            }
        }
    }

    private static func byTitle(_ lhs: Song, _ rhs: Song) -> Bool {
        lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }

    /// Nil when the dates tie; songs without a date go last.
    private static func newerFirst(_ lhs: Date?, _ rhs: Date?) -> Bool? {
        switch (lhs, rhs) {
        case let (lhs?, rhs?): lhs == rhs ? nil : lhs > rhs
        case (.some, nil): true
        case (nil, .some): false
        case (nil, nil): nil
        }
    }
}
