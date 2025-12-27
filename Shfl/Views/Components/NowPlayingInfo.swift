import SwiftUI

struct NowPlayingInfo: View {
    let title: String
    let artist: String

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            Text(artist)
                .font(.system(size: 16))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(1)
        }
    }
}

#Preview {
    NowPlayingInfo(title: "Song Title", artist: "Artist Name")
        .padding()
        .background(Color(red: 0.75, green: 0.22, blue: 0.32))
}
