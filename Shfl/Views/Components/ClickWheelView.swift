import SwiftUI

struct ClickWheelView: View {
    let isPlaying: Bool
    let onPlayPause: () -> Void
    let onSkipForward: () -> Void
    let onSkipBack: () -> Void
    let onAdd: () -> Void
    let onRemove: () -> Void

    private let wheelSize: CGFloat = 280
    private let centerButtonSize: CGFloat = 80

    var body: some View {
        ZStack {
            // Outer wheel background
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.95), Color(white: 0.88)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: wheelSize, height: wheelSize)
                .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 6)

            // Control buttons positioned around the wheel
            VStack {
                ClickWheelButton(systemName: "plus", action: onAdd)
                Spacer()
            }
            .frame(height: wheelSize - 40)

            VStack {
                Spacer()
                ClickWheelButton(systemName: "minus", action: onRemove)
            }
            .frame(height: wheelSize - 40)

            HStack {
                ClickWheelButton(systemName: "backward.end.fill", action: onSkipBack)
                Spacer()
            }
            .frame(width: wheelSize - 40)

            HStack {
                Spacer()
                ClickWheelButton(systemName: "forward.end.fill", action: onSkipForward)
            }
            .frame(width: wheelSize - 40)

            // Center play/pause button
            PlayPauseButton(isPlaying: isPlaying, action: onPlayPause)
        }
    }
}

#Preview("Paused") {
    ClickWheelView(
        isPlaying: false,
        onPlayPause: {},
        onSkipForward: {},
        onSkipBack: {},
        onAdd: {},
        onRemove: {}
    )
    .padding()
    .background(Color(red: 0.8, green: 0.2, blue: 0.3))
}

#Preview("Playing") {
    ClickWheelView(
        isPlaying: true,
        onPlayPause: {},
        onSkipForward: {},
        onSkipBack: {},
        onAdd: {},
        onRemove: {}
    )
    .padding()
    .background(Color(red: 0.8, green: 0.2, blue: 0.3))
}
