import SwiftUI

struct NowPlayingInfo: View {
    let title: String
    let artist: String

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text(artist)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    NowPlayingInfo(title: "Bohemian Rhapsody", artist: "Queen")
        .padding()
}
