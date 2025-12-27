import SwiftUI

struct ClickWheelView: View {
    @Environment(\.shuffleTheme) private var theme

    let isPlaying: Bool
    let onPlayPause: () -> Void
    let onSkipForward: () -> Void
    let onSkipBack: () -> Void
    let onVolumeUp: () -> Void
    let onVolumeDown: () -> Void

    private let wheelSize: CGFloat = 280
    private let centerButtonSize: CGFloat = 80

    private var wheelGradient: LinearGradient {
        switch theme.wheelStyle {
        case .light:
            return LinearGradient(
                colors: [Color(white: 0.95), Color(white: 0.88)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .dark:
            return LinearGradient(
                colors: [Color(white: 0.25), Color(white: 0.15)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    var body: some View {
        ZStack {
            // Outer wheel background
            Circle()
                .fill(wheelGradient)
                .frame(width: wheelSize, height: wheelSize)
                .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 6)

            // Control buttons positioned around the wheel
            VStack {
                ClickWheelButton(systemName: "plus", action: onVolumeUp, wheelStyle: theme.wheelStyle)
                Spacer()
            }
            .frame(height: wheelSize - 40)

            VStack {
                Spacer()
                ClickWheelButton(systemName: "minus", action: onVolumeDown, wheelStyle: theme.wheelStyle)
            }
            .frame(height: wheelSize - 40)

            HStack {
                ClickWheelButton(systemName: "backward.end.fill", action: onSkipBack, wheelStyle: theme.wheelStyle)
                Spacer()
            }
            .frame(width: wheelSize - 40)

            HStack {
                Spacer()
                ClickWheelButton(systemName: "forward.end.fill", action: onSkipForward, wheelStyle: theme.wheelStyle)
            }
            .frame(width: wheelSize - 40)

            // Center play/pause button
            PlayPauseButton(isPlaying: isPlaying, action: onPlayPause, wheelStyle: theme.wheelStyle)
        }
        .compositingGroup()
    }
}

#Preview("Pink Theme") {
    ClickWheelView(
        isPlaying: false,
        onPlayPause: {},
        onSkipForward: {},
        onSkipBack: {},
        onVolumeUp: {},
        onVolumeDown: {}
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
        onVolumeDown: {}
    )
    .padding()
    .background(ShuffleTheme.silver.bodyGradient)
    .environment(\.shuffleTheme, .silver)
}
