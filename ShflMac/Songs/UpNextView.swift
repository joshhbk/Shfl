import ShflCore
import SwiftUI

struct UpNextView: View {
    @Environment(ShufflePlayer.self) private var player

    var body: some View {
        if let session = player.activeSession {
            List(Array(session.songOrder.enumerated()), id: \.element.id) { position, song in
                UpNextRow(
                    position: position + 1,
                    song: song,
                    isCurrent: song.id == player.playbackState.currentSongId
                )
            }
            .accessibilityIdentifier("mac.upNext.list")
        } else {
            ContentUnavailableView(
                "Nothing Playing",
                systemImage: "shuffle",
                description: Text("Shuffle your selected songs to start a listening session.")
            )
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
