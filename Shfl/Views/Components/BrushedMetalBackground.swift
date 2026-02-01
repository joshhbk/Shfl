import SwiftUI

/// Full-screen brushed metal background using the tinted theme color
struct BrushedMetalBackground: View {
    @Environment(\.shuffleTheme) private var theme

    let highlightOffset: CGPoint

    var body: some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(theme.bodyGradientTop)
                .colorEffect(
                    ShaderLibrary.shfl_brushedMetal(
                        .float2(geometry.size.width / 2, geometry.size.height / 2),
                        .float2(highlightOffset),
                        .float(theme.brushedMetalIntensity)
                    )
                )
                .drawingGroup()  // Rasterize to reduce shader recomputation overhead
                .ignoresSafeArea()
        }
    }
}

#Preview("Silver") {
    BrushedMetalBackground(highlightOffset: .zero)
        .environment(\.shuffleTheme, .silver)
}

#Preview("Green") {
    BrushedMetalBackground(highlightOffset: .zero)
        .environment(\.shuffleTheme, .green)
}
