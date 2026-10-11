import ShflAppleMusicUI
import ShflCore
import ShflDesign
import SwiftUI

/// "Playing · 23 of 86" with the player's pill of actions.
struct PlayerHeader: View {
    @Environment(ListeningSessionHost.self) private var sessionHost
    @Environment(ShufflePlayer.self) private var player

    var body: some View {
        let timeline = sessionHost.timeline
        HStack(spacing: Spacing.s8) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s8) {
                Text(title(timeline))
                    .font(.paneTitle)
                    .accessibilityAddTraits(.isHeader)
                Text(detail(timeline))
                    .font(.secondaryText.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            PillToolbar {
                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        }
        .frame(height: 52)
    }

    private func title(_ timeline: SessionTimeline) -> String {
        switch timeline.status {
        case .idle: "Playing"
        case .ended: "Finished"
        case .active: player.playbackState.isPlaying || player.isLoadingSession ? "Playing" : "Paused"
        }
    }

    private func detail(_ timeline: SessionTimeline) -> String {
        switch timeline.status {
        case .idle: "Nothing yet"
        case .ended: "\(timeline.songCount) of \(timeline.songCount) played"
        case .active: timeline.position.map { "\($0) of \(timeline.songCount)" } ?? "\(timeline.songCount) songs"
        }
    }
}

struct SongArtwork: View {
    let song: Song?
    let size: CGFloat

    var body: some View {
        ArtworkFrame(size: size) {
            if let song {
                ArtworkView(subject: .song(id: song.id), size: size) { ArtworkPlaceholder() }
            } else {
                ArtworkPlaceholder()
            }
        }
    }
}

/// The big centred title and subtitle under the artwork.
struct PlayerHeadline: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: Spacing.s2) {
            Text(title)
                .font(.playerTitle)
                .lineLimit(1)
            MarqueeText(subtitle)
                .font(.bodyText)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }
}

extension Song {
    var byline: String {
        albumTitle.isEmpty ? artist : "\(artist) · \(albumTitle)"
    }
}

/// A song in Up Next, the whole session or Last played.
struct PlayerSongRow<Trailing: View>: View {
    let position: Int
    let song: Song
    @ViewBuilder let trailing: Trailing

    init(position: Int, song: Song, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.position = position
        self.song = song
        self.trailing = trailing()
    }

    var body: some View {
        CompactRow {
            RowIndex(position)
            SongArtwork(song: song, size: ArtworkSize.listRow)
            RowTitles(song.title, subtitle: song.artist)
            trailing
        }
        .id(song.id)
        .accessibilityIdentifier("mac.player.row.\(song.id)")
    }
}

struct PlayingNowIcon: View {
    var body: some View {
        Image(systemName: "speaker.wave.2.fill")
            .font(.meta)
            .accessibilityLabel("Playing now")
    }
}
