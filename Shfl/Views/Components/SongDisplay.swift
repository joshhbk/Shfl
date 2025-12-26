import SwiftUI

struct SongDisplay: View {
    let song: Song

    var body: some View {
        HStack(spacing: 12) {
            SongArtwork(url: song.artworkURL)

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
    let url: URL?

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.gray.opacity(0.2))
            .frame(width: 44, height: 44)
            .overlay {
                if let url {
                    AsyncImage(url: url) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Image(systemName: "music.note")
                            .foregroundStyle(.gray)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    Image(systemName: "music.note")
                        .foregroundStyle(.gray)
                }
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
