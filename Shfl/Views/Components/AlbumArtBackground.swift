import SwiftUI

/// Full-screen ambient album art background with heavy blur and dark overlay
struct AlbumArtBackground: View {
    let artworkURL: URL?
    let fallbackColor: Color
    var blurRadius: CGFloat = 25
    var overlayOpacity: Double = 0.3

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Fallback color (always visible as base layer)
                fallbackColor

                // Album art if available
                if let url = artworkURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            EmptyView()
                        case .success(let image):
                            image
                                .resizable()
                                .interpolation(.high)
                                .aspectRatio(contentMode: .fill)
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .clipped()
                                .blur(radius: blurRadius)
                                .saturation(0.8)
                        case .failure:
                            EmptyView()
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .transition(.opacity)
                }

                // Dark overlay for ambient feel
                Color.black.opacity(overlayOpacity)
            }
            .ignoresSafeArea()
        }
        .animation(.easeInOut(duration: 0.5), value: artworkURL)
    }
}

#Preview("Fallback Color") {
    AlbumArtBackground(artworkURL: nil, fallbackColor: .gray)
}

#Preview("With Album Art") {
    GeometryReader { geometry in
        ZStack {
            Image("SampleAlbumArt")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
                .blur(radius: 3)
        }
        .ignoresSafeArea()
    }
}
