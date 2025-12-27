import SwiftUI

struct CapacityIndicator: View {
    @Environment(\.shuffleTheme) private var theme

    let current: Int
    let maximum: Int

    private var pillBackground: Color {
        switch theme.textStyle {
        case .light: return .white.opacity(0.15)
        case .dark: return .black.opacity(0.1)
        }
    }

    var body: some View {
        Text("\(current)/\(maximum)")
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .foregroundStyle(theme.secondaryTextColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(pillBackground)
            )
    }
}

#Preview("Light Text") {
    VStack(spacing: 20) {
        CapacityIndicator(current: 0, maximum: 120)
        CapacityIndicator(current: 47, maximum: 120)
        CapacityIndicator(current: 120, maximum: 120)
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(ShuffleTheme.pink.bodyGradient)
    .environment(\.shuffleTheme, .pink)
}

#Preview("Dark Text") {
    VStack(spacing: 20) {
        CapacityIndicator(current: 47, maximum: 120)
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(ShuffleTheme.silver.bodyGradient)
    .environment(\.shuffleTheme, .silver)
}
