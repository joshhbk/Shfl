import ShflCore
import SwiftUI

struct UpNextView: View {
    @Environment(ListeningSessionHost.self) private var sessionHost
    @Environment(LibraryBrowser.self) private var browser

    var body: some View {
        let timeline = sessionHost.timeline
        if timeline.status == .active {
            List(Self.matching(browser.searchText, in: timeline.songs), id: \.element.id) { offset, song in
                UpNextRow(
                    position: offset + 1,
                    song: song,
                    isCurrent: song.id == timeline.current?.id
                )
            }
            .accessibilityIdentifier("mac.upNext.list")
        } else {
            ContentUnavailableView(
                "Nothing Playing",
                systemImage: "shuffle",
                description: Text("Shuffle your picks to start a listening session.")
            )
        }
    }

    static func matching(_ query: String, in songs: [Song]) -> [(offset: Int, element: Song)] {
        songs.enumerated().filter { _, song in
            query.isEmpty
                || song.title.localizedStandardContains(query)
                || song.artist.localizedStandardContains(query)
                || song.albumTitle.localizedStandardContains(query)
        }
    }
}

private struct UpNextRow: View {
    let position: Int
    let song: Song
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if isCurrent {
                    Image(systemName: "speaker.wave.2.fill")
                        .foregroundStyle(.tint)
                        .accessibilityLabel("Now playing")
                } else {
                    Text(position, format: .number)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 28, alignment: .trailing)
            .monospacedDigit()

            VStack(alignment: .leading, spacing: 1) {
                Text(song.title)
                    .fontWeight(isCurrent ? .semibold : .regular)
                Text(song.artist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("mac.upNext.row.\(song.id)")
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}
