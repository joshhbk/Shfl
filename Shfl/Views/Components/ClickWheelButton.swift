import SwiftUI

struct ClickWheelButton: View {
    let systemName: String
    let action: () -> Void
    var onPressChanged: ((Bool) -> Void)? = nil
    var wheelStyle: ShuffleTheme.WheelStyle = .light

    @State private var tapCount = 0
    @State private var isPressed = false

    private var iconColor: Color {
        switch wheelStyle {
        case .light: return Color(white: 0.3)
        case .dark: return Color(white: 0.7)
        }
    }

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(iconColor)
            .frame(width: 60, height: 60)
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isPressed {
                            isPressed = true
                            onPressChanged?(true)
                        }
                    }
                    .onEnded { value in
                        isPressed = false
                        onPressChanged?(false)

                        // Only fire action if release was within bounds (60x60 hit area)
                        let bounds = CGRect(x: 0, y: 0, width: 60, height: 60)
                        if bounds.contains(value.location) {
                            tapCount += 1
                            action()
                        }
                    }
            )
            .sensoryFeedback(.impact(weight: .heavy, intensity: 0.8), trigger: tapCount)
    }
}

#Preview("Light Wheel") {
    HStack(spacing: 20) {
        ClickWheelButton(systemName: "plus", action: {}, wheelStyle: .light)
        ClickWheelButton(systemName: "minus", action: {}, wheelStyle: .light)
        ClickWheelButton(systemName: "backward.end.fill", action: {}, wheelStyle: .light)
        ClickWheelButton(systemName: "forward.end.fill", action: {}, wheelStyle: .light)
    }
    .padding()
    .background(Color(white: 0.9))
}

#Preview("Dark Wheel") {
    HStack(spacing: 20) {
        ClickWheelButton(systemName: "plus", action: {}, wheelStyle: .dark)
        ClickWheelButton(systemName: "minus", action: {}, wheelStyle: .dark)
        ClickWheelButton(systemName: "backward.end.fill", action: {}, wheelStyle: .dark)
        ClickWheelButton(systemName: "forward.end.fill", action: {}, wheelStyle: .dark)
    }
    .padding()
    .background(Color(white: 0.2))
}
