import SwiftUI

struct PlayPauseButton: View {
    let isPlaying: Bool
    let action: () -> Void
    let theme: ShuffleTheme

    @State private var isPressed = false

    private let buttonSize: CGFloat = 150
    private let iconSize: CGFloat = 40

    private var buttonBackgroundColor: Color {
        theme.bodyGradientTop
    }

    private var iconColor: Color {
        theme.centerButtonIconColor
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(buttonBackgroundColor)
                .frame(width: buttonSize, height: buttonSize)
                .shadow(
                    color: .black.opacity(0.1),
                    radius: isPressed ? ClickWheelFeedback.centerPressedShadowRadius : ClickWheelFeedback.centerNormalShadowRadius,
                    x: 0,
                    y: isPressed ? ClickWheelFeedback.centerPressedShadowY : ClickWheelFeedback.centerNormalShadowY
                )

            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: iconSize, weight: .medium))
                .foregroundStyle(iconColor)
                .offset(x: isPlaying ? 0 : 3)
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
                    // Only fire action if release was within bounds
                    let bounds = CGRect(x: 0, y: 0, width: buttonSize, height: buttonSize)
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

#Preview("Pink Theme") {
    VStack(spacing: 40) {
        PlayPauseButton(isPlaying: false, action: {}, theme: .pink)
        PlayPauseButton(isPlaying: true, action: {}, theme: .pink)
    }
    .padding()
    .background(ShuffleTheme.pink.bodyGradient)
}

#Preview("Silver Theme") {
    VStack(spacing: 40) {
        PlayPauseButton(isPlaying: false, action: {}, theme: .silver)
        PlayPauseButton(isPlaying: true, action: {}, theme: .silver)
    }
    .padding()
    .background(ShuffleTheme.silver.bodyGradient)
}

#Preview("Blue Theme") {
    VStack(spacing: 40) {
        PlayPauseButton(isPlaying: false, action: {}, theme: .blue)
        PlayPauseButton(isPlaying: true, action: {}, theme: .blue)
    }
    .padding()
    .background(ShuffleTheme.blue.bodyGradient)
}
