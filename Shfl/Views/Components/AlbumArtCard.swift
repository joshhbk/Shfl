import MusicKit
import SwiftUI

/// Floating album art card with layered shadows and subtle border
struct AlbumArtCard: View {
    let artworkURL: URL?
    let songId: String?
    var size: CGFloat = 280

    @State private var artwork: Artwork?

    init(artworkURL: URL?, songId: String? = nil, size: CGFloat = 280) {
        self.artworkURL = artworkURL
        self.songId = songId
        self.size = size
    }

    var body: some View {
        Group {
            if let artwork {
                ArtworkImage(artwork, width: size, height: size)
            } else if let artworkURL, artworkURL.scheme == "https" || artworkURL.scheme == "http" {
                AsyncImage(url: artworkURL) { phase in
                    switch phase {
                    case .empty:
                        placeholderView
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    case .failure:
                        placeholderView
                    @unknown default:
                        placeholderView
                    }
                }
            } else {
                placeholderView
            }
        }
        .frame(width: size, height: size)
        .background(Color.black.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
        )
        // Layered shadows for depth
        .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
        .shadow(color: .black.opacity(0.20), radius: 8, x: 0, y: 4)
        .shadow(color: .black.opacity(0.10), radius: 20, x: 0, y: 10)
        .task(id: songId) {
            artwork = nil
            guard let songId else { return }

            if let cachedArtwork = ArtworkCache.shared.artwork(for: songId) {
                artwork = cachedArtwork
                return
            }

            ArtworkCache.shared.requestArtwork(for: songId)

            for await loadedArtwork in ArtworkCache.shared.artworkUpdates(for: songId) {
                artwork = loadedArtwork
                break
            }
        }
    }

    private var placeholderView: some View {
        ZStack {
            Color(white: 0.15)
            Image(systemName: "music.note")
                .font(.system(size: size * 0.3))
                .foregroundStyle(.white.opacity(0.3))
        }
    }
}

#Preview("With Album Art") {
    ZStack {
        Color.black
        AlbumArtCard(
            artworkURL: URL(string: "https://picsum.photos/400")
        )
    }
}

#Preview("No Album Art") {
    ZStack {
        Color.black
        AlbumArtCard(artworkURL: nil)
    }
}
