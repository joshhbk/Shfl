import ShflCore
import ShflDesign
import SwiftUI

/// One song in a `SongList`: its cells in `columns`, read by VoiceOver as one sentence with a pick action.
struct SongRow<Cells: View>: View {
    private let item: SongItem
    private let stat: SongStat?
    private let columns: [ListColumn]
    private let cells: Cells

    init(_ item: SongItem, stat: SongStat?, columns: [ListColumn], @ViewBuilder cells: (SongItem) -> Cells) {
        self.item = item
        self.stat = stat
        self.columns = columns
        self.cells = cells(item)
    }

    var body: some View {
        ListColumns(columns) { cells }
            .frame(minHeight: SongListMetrics.rowHeight)
            .contentShape(.rect)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(SongSpeech.describe(item.song, mark: item.mark, stat: stat))
            .accessibilityAction(named: SongSpeech.pickActionName(for: item.mark), item.togglePick)
            .accessibilityIdentifier("mac.songs.row.\(item.song.id)")
    }
}

enum SongListMetrics {
    static let rowHeight: CGFloat = 46
    static let headerHeight: CGFloat = 28
    static let horizontalInset: CGFloat = 20
    /// macOS adds its own padding inside a list row's insets, so rows ask for less to land on `horizontalInset`.
    static let rowInset: CGFloat = horizontalInset - 8
}

enum SongSpeech {
    static func describe(_ song: Song, mark: SongMark, stat: SongStat?, now: Date = .now) -> String {
        let pick = switch (mark.pick, mark.joinsNextShuffle) {
        case (.picked, true): "Picked, plays from the next shuffle."
        case (.picked, false): "Picked."
        case (.open, _): "Not picked."
        case (.full, _): "Not picked. Picks are full."
        }
        return [
            ([song.title, song.artist, song.albumTitle].filter { !$0.isEmpty }.joined(separator: ", ") + "."),
            stat?.spoken(for: song, now: now) ?? "",
            SongDuration.spoken(song.duration),
            mark.isPlaying ? "Playing now." : "",
            pick,
        ]
        .filter { !$0.isEmpty }
        .joined(separator: " ")
    }

    static func pickActionName(for mark: SongMark) -> String {
        mark.isPicked ? "Remove from Picks" : "Add to Picks"
    }
}
