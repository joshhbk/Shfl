import SwiftUI

/// Full-screen album art background with minimal blur
struct AlbumArtBackground: View {
    let artworkURL: URL?
    let fallbackColor: Color
    var blurRadius: CGFloat = 3

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
                            ProgressView()
                        case .success(let image):
                            image
                                .resizable()
                                .interpolation(.high)
                                .aspectRatio(contentMode: .fill)
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .clipped()
                                .blur(radius: blurRadius)
                        case .failure:
                            EmptyView()
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .transition(.opacity)
                }
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
