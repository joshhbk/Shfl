import SwiftUI

struct ClickWheelView: View {
    @Environment(\.shuffleTheme) private var theme

    @State private var pressPosition: WheelPressPosition = .none

    let isPlaying: Bool
    let onPlayPause: () -> Void
    let onSkipForward: () -> Void
    let onSkipBack: () -> Void
    let onVolumeUp: () -> Void
    let onVolumeDown: () -> Void
    let highlightOffset: CGPoint
    var scale: CGFloat = 1.0

    private var wheelSize: CGFloat { 280 * scale }
    private var centerButtonSize: CGFloat { 150 * scale }

    // Position buttons at the midpoint of the ring
    // Ring spans from centerButtonSize/2 to wheelSize/2
    // Midpoint = (centerButtonSize/2 + wheelSize/2) / 2 = (centerButtonSize + wheelSize) / 4
    // Button center should be at this distance from wheel center
    // With VStack { Button; Spacer }, button center = frame/2 - 30 (button is 60pt tall)
    // So frame = 2 * (midpoint + 30)
    private var buttonContainerSize: CGFloat {
        let ringMidpoint = (centerButtonSize + wheelSize) / 4
        return 2 * (ringMidpoint + 30)
    }

    private var wheelColor: Color {
        switch theme.wheelStyle {
        case .light:
            return Color(white: 0.95)
        case .dark:
            return Color(white: 0.08)
        }
    }

    var body: some View {
        ZStack {
            // Outer wheel - clean and simple
            Circle()
                .fill(wheelColor)
                .frame(width: wheelSize, height: wheelSize)
                .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 6)

            // Control buttons positioned around the wheel
            VStack {
                ClickWheelButton(
                    systemName: "plus",
                    action: onVolumeUp,
                    onPressChanged: { isPressed in pressPosition = isPressed ? .top : .none },
                    wheelStyle: theme.wheelStyle
                )
                Spacer()
            }
            .frame(height: buttonContainerSize)

            VStack {
                Spacer()
                ClickWheelButton(
                    systemName: "minus",
                    action: onVolumeDown,
                    onPressChanged: { isPressed in pressPosition = isPressed ? .bottom : .none },
                    wheelStyle: theme.wheelStyle
                )
            }
            .frame(height: buttonContainerSize)

            HStack {
                ClickWheelButton(
                    systemName: "backward.end.fill",
                    action: onSkipBack,
                    onPressChanged: { isPressed in pressPosition = isPressed ? .left : .none },
                    wheelStyle: theme.wheelStyle
                )
                Spacer()
            }
            .frame(width: buttonContainerSize)

            HStack {
                Spacer()
                ClickWheelButton(
                    systemName: "forward.end.fill",
                    action: onSkipForward,
                    onPressChanged: { isPressed in pressPosition = isPressed ? .right : .none },
                    wheelStyle: theme.wheelStyle
                )
            }
            .frame(width: buttonContainerSize)

            // Center play/pause button
            PlayPauseButton(isPlaying: isPlaying, action: onPlayPause, theme: theme, highlightOffset: highlightOffset, scale: scale)
        }
        .compositingGroup()
        .scaleEffect(pressPosition != .none ? ClickWheelFeedback.wheelPressScale : 1.0)
        .rotation3DEffect(
            .degrees(pressPosition != .none ? ClickWheelFeedback.tiltAngle : 0),
            axis: pressPosition.rotationAxis,
            perspective: ClickWheelFeedback.perspective
        )
        .animation(
            .spring(response: ClickWheelFeedback.springResponse, dampingFraction: ClickWheelFeedback.springDampingFraction),
            value: pressPosition
        )
    }
}

#Preview("Pink Theme") {
    ClickWheelView(
        isPlaying: false,
        onPlayPause: {},
        onSkipForward: {},
        onSkipBack: {},
        onVolumeUp: {},
        onVolumeDown: {},
        highlightOffset: .zero
    )
    .padding()
    .background(ShuffleTheme.pink.bodyGradient)
    .environment(\.shuffleTheme, .pink)
}

#Preview("Silver Theme") {
    ClickWheelView(
        isPlaying: true,
        onPlayPause: {},
        onSkipForward: {},
        onSkipBack: {},
        onVolumeUp: {},
        onVolumeDown: {},
        highlightOffset: .zero
    )
    .padding()
    .background(ShuffleTheme.silver.bodyGradient)
    .environment(\.shuffleTheme, .silver)
}
