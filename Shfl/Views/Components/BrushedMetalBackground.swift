import SwiftUI

struct BrushedMetalBackground: View {
    let baseColor: Color
    let intensity: CGFloat

    init(baseColor: Color, intensity: CGFloat = 0.5) {
        self.baseColor = baseColor
        self.intensity = intensity
    }

    var body: some View {
        GeometryReader { geometry in
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            let maxRadius = max(geometry.size.width, geometry.size.height)

            Canvas { context, size in
                let ringSpacing: CGFloat = 2.0
                let rings = Self.ringCount(for: maxRadius, spacing: ringSpacing)

                for i in 0..<rings {
                    let radius = CGFloat(i) * ringSpacing
                    let opacity = Self.ringOpacity(at: i, intensity: intensity)

                    let ringColor = Color.white.opacity(opacity)

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
        }
        .background(baseColor)
    }

    // MARK: - Calculations (static for testability)

    static func ringCount(for radius: CGFloat, spacing: CGFloat) -> Int {
        Int(radius / spacing)
    }

    static func ringOpacity(at index: Int, intensity: CGFloat) -> CGFloat {
        guard intensity > 0 else { return 0 }

        // Alternate between lighter and darker rings
        let baseOpacity: CGFloat = index.isMultiple(of: 2) ? 0.08 : 0.04
        return baseOpacity * intensity
    }
}

#Preview {
    BrushedMetalBackground(baseColor: Color(red: 0.75, green: 0.75, blue: 0.75))
}
