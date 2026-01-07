import SwiftUI

struct BrushedMetalBackground: View {
    let baseColor: Color
    let intensity: CGFloat
    let highlightOffset: CGPoint
    let motionEnabled: Bool
    let highlightColor: Color

    init(
        baseColor: Color,
        intensity: CGFloat = 0.5,
        highlightOffset: CGPoint = .zero,
        motionEnabled: Bool = true,
        highlightColor: Color = .white
    ) {
        self.baseColor = baseColor
        self.intensity = intensity
        self.highlightOffset = motionEnabled ? highlightOffset : .zero
        self.motionEnabled = motionEnabled
        self.highlightColor = highlightColor
    }

    var body: some View {
        GeometryReader { geometry in
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            
            Rectangle()
                .fill(baseColor)
                .colorEffect(
                    ShaderLibrary.shfl_brushedMetal(
                        .float2(center),
                        .float2(highlightOffset),
                        .float(intensity)
                    )
                )
        }
    }


}

#Preview {
    BrushedMetalBackground(baseColor: Color(red: 0.75, green: 0.75, blue: 0.75))
}
