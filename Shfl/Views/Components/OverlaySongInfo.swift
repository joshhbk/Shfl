import SwiftUI

/// Song info styled for overlay on album art - always white text with shadow
struct OverlaySongInfo: View {
    let title: String
    let artist: String

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 20, weight: .semibold))
                .lineLimit(1)

            Text(artist)
                .font(.system(size: 16, weight: .regular))
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
        .multilineTextAlignment(.center)
    }
}

#Preview {
    ZStack {
        Color.blue

        OverlaySongInfo(title: "Song Title", artist: "Artist Name")
    }
}
