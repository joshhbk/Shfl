import ShflAppleMusicUI
import ShflCore
import SwiftUI

struct NowPlayingArtwork: View {
    let song: Song?

    private static let size: CGFloat = 44

    var body: some View {
        Group {
            if let song {
                ArtworkView(subject: .song(id: song.id), size: Self.size) {
                    ArtworkPlaceholder()
                }
            } else {
                ArtworkPlaceholder()
            }
        }
        .frame(width: Self.size, height: Self.size)
        .clipShape(.rect(cornerRadius: 6))
        .accessibilityHidden(true)
    }
}

private struct ArtworkPlaceholder: View {
    var body: some View {
        Rectangle()
            .fill(.quaternary)
            .overlay {
                Image(systemName: "music.note")
                    .foregroundStyle(.secondary)
            }
    }
}
