import SwiftUI

struct NowPlayingInfo: View {
    @Environment(\.shuffleTheme) private var theme

    let title: String
    let artist: String

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(theme.textColor)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            Text(artist)
                .font(.system(size: 16))
                .foregroundStyle(theme.secondaryTextColor)
                .lineLimit(1)
        }
    }
}

#Preview("Light Text") {
    NowPlayingInfo(title: "Song Title", artist: "Artist Name")
        .padding()
        .background(ShuffleTheme.pink.bodyGradient)
        .environment(\.shuffleTheme, .pink)
}

#Preview("Dark Text") {
    NowPlayingInfo(title: "Song Title", artist: "Artist Name")
        .padding()
        .background(ShuffleTheme.silver.bodyGradient)
        .environment(\.shuffleTheme, .silver)
}
