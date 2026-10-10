import ShflCore
import SwiftUI

struct SongDisplay: View {
    let song: Song

    var body: some View {
        HStack(spacing: 12) {
            EntityArtwork(subject: .song(id: song.id))

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
