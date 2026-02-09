import SwiftUI

/// Full-screen background with tinted theme gradient and subtle grain texture
struct BrushedMetalBackground: View {
    @Environment(\.shuffleTheme) private var theme

    var body: some View {
        Rectangle()
            .fill(theme.bodyGradientTop)
            .ignoresSafeArea()
    }
}

#Preview("Silver") {
    BrushedMetalBackground()
        .environment(\.shuffleTheme, .silver)
}

#Preview("Green") {
    BrushedMetalBackground()
        .environment(\.shuffleTheme, .green)
}
