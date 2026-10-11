import ShflCore
import ShflDesign
import SwiftUI

/// The title with the marks that ride on it, over a subtitle the screen chooses.
struct SongTitles: View {
    let song: Song
    let subtitle: String
    let mark: SongMark

    init(_ item: SongItem, subtitle: String) {
        song = item.song
        mark = item.mark
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: Spacing.s6) {
                Text(song.title)
                    .font(.bodyEmphasis)
                    .foregroundStyle(.primary)
                    .layoutPriority(1)
                if mark.isPlaying { NowPlayingGlyph() }
                if mark.joinsNextShuffle { AccentTag("Next shuffle") }
            }
            Text(subtitle)
                .font(.secondaryText)
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct RowDetail: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.secondaryText)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct RowStat: View {
    let text: String

    init(_ stat: SongStat, of song: Song) {
        text = stat.text(for: song)
    }

    var body: some View {
        Text(text)
            .font(.secondaryText.monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}

struct RowDuration: View {
    let duration: TimeInterval?

    init(_ duration: TimeInterval?) {
        self.duration = duration
    }

    var body: some View {
        Text(SongDuration.text(duration))
            .font(.secondaryText.monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}

/// The row's + or ✓. Not a Tab stop: the list's ↩ and ⌫ do the same thing.
struct PickToggle: View {
    let item: SongItem

    init(_ item: SongItem) {
        self.item = item
    }

    var body: some View {
        Toggle(isOn: Binding(get: { item.mark.isPicked }, set: { _ in item.togglePick() })) {
            Text(item.mark.isPicked ? "Remove \(item.song.title) from Picks" : "Add \(item.song.title) to Picks")
        }
        .toggleStyle(.pick)
        .disabled(item.mark.pick == .full)
        .focusable(false)
        .accessibilityIdentifier("mac.songs.pick.\(item.song.id)")
    }
}
