import SwiftUI

/// Full-screen brushed metal background using the tinted theme color
struct BrushedMetalBackground: View {
    @Environment(\.shuffleTheme) private var theme

    var body: some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(theme.bodyGradientTop)
                .colorEffect(
                    ShaderLibrary.shfl_brushedMetal(
                        .float2(geometry.size.width / 2, geometry.size.height / 2),
                        .float(theme.brushedMetalIntensity)
                    )
                )
                .ignoresSafeArea()
        }
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
