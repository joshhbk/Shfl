import SwiftUI

struct SongRow: View {
    let song: Song
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 44, height: 44)
                    .overlay {
                        if let url = song.artworkURL {
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

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isSelected ? .blue : .gray.opacity(0.4))
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    VStack(spacing: 0) {
        SongRow(
            song: Song(id: "1", title: "Bohemian Rhapsody", artist: "Queen", albumTitle: "A Night at the Opera", artworkURL: nil),
            isSelected: false,
            onToggle: {}
        )
        Divider()
        SongRow(
            song: Song(id: "2", title: "Stairway to Heaven", artist: "Led Zeppelin", albumTitle: "Led Zeppelin IV", artworkURL: nil),
            isSelected: true,
            onToggle: {}
        )
    }
}
