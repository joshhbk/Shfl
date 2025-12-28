import SwiftUI

struct PlayPauseButton: View {
    let isPlaying: Bool
    let action: () -> Void
    var wheelStyle: ShuffleTheme.WheelStyle = .light

    @State private var isPressed = false

    private var buttonBackgroundColor: Color {
        switch wheelStyle {
        case .light: return .white
        case .dark: return Color(white: 0.1)
        }
    }

    private var iconColor: Color {
        switch wheelStyle {
        case .light: return .black
        case .dark: return .white
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(buttonBackgroundColor)
                .frame(width: 80, height: 80)
                .shadow(
                    color: .black.opacity(0.1),
                    radius: isPressed ? ClickWheelFeedback.centerPressedShadowRadius : ClickWheelFeedback.centerNormalShadowRadius,
                    x: 0,
                    y: isPressed ? ClickWheelFeedback.centerPressedShadowY : ClickWheelFeedback.centerNormalShadowY
                )

            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(iconColor)
                .offset(x: isPlaying ? 0 : 2)
        }
        .scaleEffect(isPressed ? ClickWheelFeedback.centerPressScale : 1.0)
        .animation(.spring(response: ClickWheelFeedback.springResponse, dampingFraction: ClickWheelFeedback.springDampingFraction), value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed {
                        isPressed = true
                    }
                }
                .onEnded { value in
                    isPressed = false
                    // Only fire action if release was within bounds (80x80 button)
                    let bounds = CGRect(x: 0, y: 0, width: 80, height: 80)
                    if bounds.contains(value.location) {
                        action()
                    }
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isPlaying ? "Pause" : "Play")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            action()
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: isPlaying)
    }
}

#Preview("Light Wheel") {
    VStack(spacing: 40) {
        PlayPauseButton(isPlaying: false, wheelStyle: .light) {}
        PlayPauseButton(isPlaying: true, wheelStyle: .light) {}
    }
    .padding()
    .background(Color(white: 0.9))
}

#Preview("Dark Wheel") {
    VStack(spacing: 40) {
        PlayPauseButton(isPlaying: false, wheelStyle: .dark) {}
        PlayPauseButton(isPlaying: true, wheelStyle: .dark) {}
    }
    .padding()
    .background(Color(white: 0.2))
}
