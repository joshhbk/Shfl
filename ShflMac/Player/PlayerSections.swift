import ShflCore
import ShflDesign
import SwiftUI

/// The next few songs, marking any that have left the pool since the shuffle.
struct UpNextSection: View {
    let timeline: SessionTimeline

    private static let rowCount = 5

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s4) {
            SectionHeader("Up Next")
            if timeline.upcoming.isEmpty {
                Text("This is the last song in the session.")
                    .font(.secondaryText)
                    .foregroundStyle(.secondary)
                    .padding(.top, Spacing.s8)
            }
            ForEach(Array(timeline.upcoming.prefix(Self.rowCount).enumerated()), id: \.element.id) { offset, song in
                PlayerSongRow(position: timeline.played.count + 2 + offset, song: song) {
                    if timeline.leftPool.contains(song.id) {
                        OutlinedTag("Left pool")
                            .accessibilityLabel("No longer in the pool, still plays this session")
                    }
                }
            }
        }
        .accessibilityIdentifier("mac.player.upNext")
    }
}

/// Every song in the session, scrolled to the one playing. Read-only.
struct SessionList: View {
    let timeline: SessionTimeline

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s4) {
            SectionHeader("Session")
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(timeline.songs.enumerated()), id: \.element.id) { offset, song in
                            let isCurrent = song.id == timeline.current?.id
                            PlayerSongRow(position: offset + 1, song: song) {
                                if isCurrent { PlayingNowIcon() }
                                if timeline.leftPool.contains(song.id) { OutlinedTag("Left pool") }
                            }
                            .fontWeight(isCurrent ? .bold : nil)
                            .opacity(offset < timeline.played.count ? 0.8 : 1)
                            .rowHighlight(isCurrent)
                        }
                    }
                    .padding(.horizontal, Spacing.s8)
                }
                .padding(.horizontal, -Spacing.s8)
                .onAppear {
                    if let current = timeline.current { proxy.scrollTo(current.id, anchor: .center) }
                }
            }
        }
        .accessibilityIdentifier("mac.player.session")
    }
}

/// The end of a finished session.
struct LastPlayedSection: View {
    let timeline: SessionTimeline
    let endedAt: Date

    private static let rowCount = 5

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s4) {
            SectionHeader("Last played") {
                Text("Ended \(endedAt.formatted(date: .omitted, time: .shortened))")
            }
            let start = max(timeline.played.count - Self.rowCount, 0)
            ForEach(Array(timeline.played[start...].enumerated()), id: \.element.id) { offset, song in
                PlayerSongRow(position: start + offset + 1, song: song)
            }
        }
    }
}

/// What Up Next says before anything has played.
struct UpNextPlaceholder: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s8) {
            SectionHeader("Up Next")
            Text("Songs appear here once a shuffle starts.")
                .font(.secondaryText)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
