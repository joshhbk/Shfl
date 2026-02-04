import Combine
import MusicKit
import SwiftUI

struct SongDisplay: View {
    let song: Song

    var body: some View {
        HStack(spacing: 12) {
            SongArtwork(songId: song.id)

            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(song.artist)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

struct SongArtwork: View {
    let songId: String

    @State private var artwork: Artwork?

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.gray.opacity(0.2))
            .frame(width: 44, height: 44)
            .overlay {
                if let artwork {
                    ArtworkImage(artwork, width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    Image(systemName: "music.note")
                        .foregroundStyle(.gray)
                }
            }
            .onAppear {
                // Check cache first, request if not present
                artwork = ArtworkCache.shared.artwork(for: songId)
                if artwork == nil {
                    ArtworkCache.shared.requestArtwork(for: songId)
                }
            }
            .onReceive(
                NotificationCenter.default.publisher(for: ArtworkCache.artworkDidLoad)
                    .filter { ($0.userInfo?["songId"] as? String) == songId }
            ) { _ in
                artwork = ArtworkCache.shared.artwork(for: songId)
            }
    }
}

#Preview {
    SongDisplay(
        song: Song(
            id: "1",
            title: "Bohemian Rhapsody",
            artist: "Queen",
            albumTitle: "A Night at the Opera",
            artworkURL: nil
        )
    )
    .padding()
}
