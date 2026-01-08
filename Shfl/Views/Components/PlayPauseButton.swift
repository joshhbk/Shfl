import SwiftUI

struct PlayPauseButton: View {
    let isPlaying: Bool
    let action: () -> Void
    let theme: ShuffleTheme
    let highlightOffset: CGPoint

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
                .colorEffect(
                    ShaderLibrary.shfl_brushedMetal(
                        .float2(buttonSize / 2, buttonSize / 2),
                        .float2(highlightOffset),
                        .float(theme.brushedMetalIntensity)
                    )
                )
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
                        HapticFeedback.medium.trigger()
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
    }
}

#Preview("Pink Theme") {
    VStack(spacing: 40) {
        PlayPauseButton(isPlaying: false, action: {}, theme: .pink, highlightOffset: .zero)
        PlayPauseButton(isPlaying: true, action: {}, theme: .pink, highlightOffset: .zero)
    }
    .padding()
    .background(ShuffleTheme.pink.bodyGradient)
}

#Preview("Silver Theme") {
    VStack(spacing: 40) {
        PlayPauseButton(isPlaying: false, action: {}, theme: .silver, highlightOffset: .zero)
        PlayPauseButton(isPlaying: true, action: {}, theme: .silver, highlightOffset: .zero)
    }
    .padding()
    .background(ShuffleTheme.silver.bodyGradient)
}

#Preview("Blue Theme") {
    VStack(spacing: 40) {
        PlayPauseButton(isPlaying: false, action: {}, theme: .blue, highlightOffset: .zero)
        PlayPauseButton(isPlaying: true, action: {}, theme: .blue, highlightOffset: .zero)
    }
    .padding()
    .background(ShuffleTheme.blue.bodyGradient)
}
