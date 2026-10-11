import ShflAppleMusicUI
import ShflCore
import ShflDesign
import SwiftUI

/// The player's pill of actions, pinned to the top trailing corner.
struct PlayerHeader: View {
    var body: some View {
        HStack {
            Spacer(minLength: 0)
            PillToolbar {
                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        }
        .frame(height: 52)
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

/// What the player says about the session: the song that's playing, or why there isn't one.
struct SessionCopy {
    let title: String
    let subtitle: String

    init(timeline: SessionTimeline, play: TransportIntents.Play) {
        switch (timeline.status, timeline.current) {
        case (.active, let song?):
            title = song.title
            subtitle = song.byline
        case (.active, nil):
            title = "Loading…"
            subtitle = ""
        case (.ended, _):
            title = "That was the whole session"
            subtitle = "All \(timeline.songCount) songs played. " + Self.nextStep(play)
        case (.idle, _):
            title = "Just press Play"
            subtitle = Self.nextStep(play)
        }
    }

    private static func nextStep(_ play: TransportIntents.Play) -> String {
        switch play {
        case .autofillAndShuffle(let count):
            "With no picks, Play fills them with \(count) random songs from your library, then shuffles."
        case .shuffleDraft(let count):
            "Play shuffles your \(count) picks."
        case .pause, .resume:
            ""
        }
    }
}

/// The session's copy, centred under the artwork.
struct SessionHeadline: View {
    let timeline: SessionTimeline

    @Environment(ListeningSessionHost.self) private var sessionHost

    var body: some View {
        let copy = SessionCopy(timeline: timeline, play: sessionHost.intents.play)
        PlayerHeadline(title: copy.title, subtitle: copy.subtitle)
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
