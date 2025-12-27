import SwiftUI

struct ClickWheelButton: View {
    let systemName: String
    let action: () -> Void
    var wheelStyle: ShuffleTheme.WheelStyle = .light

    @State private var tapCount = 0

    private var iconColor: Color {
        switch wheelStyle {
        case .light: return Color(white: 0.3)
        case .dark: return Color(white: 0.7)
        }
    }

    var body: some View {
        Button(action: {
            tapCount += 1
            action()
        }) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .light), trigger: tapCount)
    }
}

#Preview("Light Wheel") {
    HStack(spacing: 20) {
        ClickWheelButton(systemName: "plus", wheelStyle: .light) {}
        ClickWheelButton(systemName: "minus", wheelStyle: .light) {}
        ClickWheelButton(systemName: "backward.end.fill", wheelStyle: .light) {}
        ClickWheelButton(systemName: "forward.end.fill", wheelStyle: .light) {}
    }
    .padding()
    .background(Color(white: 0.9))
}

#Preview("Dark Wheel") {
    HStack(spacing: 20) {
        ClickWheelButton(systemName: "plus", wheelStyle: .dark) {}
        ClickWheelButton(systemName: "minus", wheelStyle: .dark) {}
        ClickWheelButton(systemName: "backward.end.fill", wheelStyle: .dark) {}
        ClickWheelButton(systemName: "forward.end.fill", wheelStyle: .dark) {}
    }
    .padding()
    .background(Color(white: 0.2))
}
