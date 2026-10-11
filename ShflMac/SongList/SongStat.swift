import Foundation
import ShflCore
import ShflDesign

/// The number a song list shows beside the album, chosen by how the list is sorted.
enum SongStat: Equatable {
    case plays
    case lastPlayed
    case added

    init(_ sort: SortOption) {
        switch sort {
        case .mostPlayed, .alphabetical: self = .plays
        case .recentlyPlayed: self = .lastPlayed
        case .recentlyAdded: self = .added
        }
    }

    var sort: SortOption {
        switch self {
        case .plays: .mostPlayed
        case .lastPlayed: .recentlyPlayed
        case .added: .recentlyAdded
        }
    }

    var column: ListColumn {
        switch self {
        case .plays: Self.playsColumn
        case .lastPlayed: Self.lastPlayedColumn
        case .added: Self.addedColumn
        }
    }

    private static let playsColumn = ListColumn.stat("plays", width: 48)
    private static let lastPlayedColumn = ListColumn.stat("lastPlayed", width: 78)
    private static let addedColumn = ListColumn.stat("added", width: 64)

    var title: String {
        switch self {
        case .plays: "Plays"
        case .lastPlayed: "Last Played"
        case .added: "Added"
        }
    }

    func text(for song: Song, now: Date = .now, calendar: Calendar = .current) -> String {
        switch self {
        case .plays: song.playCount.formatted()
        case .lastPlayed: song.lastPlayedDate.map { Self.day($0, now: now, calendar: calendar) } ?? "—"
        case .added: song.dateAdded.map { Self.day($0, now: now, calendar: calendar) } ?? "—"
        }
    }

    func spoken(for song: Song, now: Date = .now, calendar: Calendar = .current) -> String {
        switch self {
        case .plays:
            song.playCount == 1 ? "1 play." : "\(song.playCount.formatted()) plays."
        case .lastPlayed:
            song.lastPlayedDate.map { "Last played \(Self.day($0, now: now, calendar: calendar))." } ?? "Never played."
        case .added:
            song.dateAdded.map { "Added \(Self.day($0, now: now, calendar: calendar))." } ?? ""
        }
    }

    private static func day(_ date: Date, now: Date, calendar: Calendar) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        var style = Date.FormatStyle(date: .omitted, time: .omitted, calendar: calendar, timeZone: calendar.timeZone)
            .day()
            .month(.abbreviated)
        if !calendar.isDate(date, equalTo: now, toGranularity: .year) {
            style = style.year()
        }
        return date.formatted(style)
    }
}

enum SongDuration {
    static func text(_ duration: TimeInterval?) -> String {
        guard let duration, duration > 0 else { return "" }
        let pattern: Duration.TimeFormatStyle.Pattern = duration >= 3600 ? .hourMinuteSecond : .minuteSecond
        return Duration.seconds(duration.rounded()).formatted(.time(pattern: pattern))
    }

    static func spoken(_ duration: TimeInterval?) -> String {
        guard let duration, duration > 0 else { return "" }
        let units = Duration.seconds(duration.rounded()).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))
        return "\(units)."
    }
}
