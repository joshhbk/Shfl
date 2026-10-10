import ShflCore
import SwiftUI

struct NowPlayingTitles: View {
    let song: Song?
    let notice: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(song?.title ?? "Not Playing")
                .font(.headline)
                .lineLimit(1)
                .accessibilityIdentifier("mac.nowPlaying.title")
            if let notice {
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .accessibilityIdentifier("mac.nowPlaying.notice")
            } else if let song {
                Text(song.artist)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .accessibilityIdentifier("mac.nowPlaying.artist")
            }
        }
    }
}
