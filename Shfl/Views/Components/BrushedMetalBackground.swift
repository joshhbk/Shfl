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
            let maxRadius = max(geometry.size.width, geometry.size.height)
            let highlightCenter = Self.highlightCenter(base: center, offset: highlightOffset)

            ZStack {
                // Base color
                baseColor

                // Concentric rings
                Canvas { context, _ in
                    let ringSpacing: CGFloat = 2.0
                    let rings = Self.ringCount(for: maxRadius, spacing: ringSpacing)

                    for i in 0..<rings {
                        let radius = CGFloat(i) * ringSpacing
                        let opacity = Self.ringOpacity(at: i, intensity: intensity)
                        let ringColor = highlightColor.opacity(opacity)

                        let path = Path { p in
                            p.addArc(
                                center: center,
                                radius: radius,
                                startAngle: .zero,
                                endAngle: .degrees(360),
                                clockwise: false
                            )
                        }

                        context.stroke(path, with: .color(ringColor), lineWidth: 1)
                    }
                }

                // Specular highlight - tight glint that moves with tilt
                RadialGradient(
                    colors: [
                        highlightColor.opacity(0.35 * intensity),
                        highlightColor.opacity(0.20 * intensity),
                        highlightColor.opacity(0.05 * intensity),
                        Color.clear
                    ],
                    center: UnitPoint(
                        x: highlightCenter.x / geometry.size.width,
                        y: highlightCenter.y / geometry.size.height
                    ),
                    startRadius: 0,
                    endRadius: maxRadius * 0.35
                )
            }
        }
    }

    // MARK: - Calculations

    static func ringCount(for radius: CGFloat, spacing: CGFloat) -> Int {
        Int(radius / spacing)
    }

    static func ringOpacity(at index: Int, intensity: CGFloat) -> CGFloat {
        guard intensity > 0 else { return 0 }
        let baseOpacity: CGFloat = index.isMultiple(of: 2) ? 0.06 : 0.03
        return baseOpacity * intensity
    }

    static func highlightCenter(base: CGPoint, offset: CGPoint) -> CGPoint {
        CGPoint(x: base.x + offset.x, y: base.y + offset.y)
    }
}

#Preview {
    BrushedMetalBackground(baseColor: Color(red: 0.75, green: 0.75, blue: 0.75))
}
