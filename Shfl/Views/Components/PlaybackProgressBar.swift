import SwiftUI

struct PlaybackProgressBar: View {
    @Environment(\.shuffleTheme) private var theme

    let currentTime: TimeInterval
    let duration: TimeInterval
    let onSeek: (TimeInterval) -> Void

    @State private var isDragging = false
    @State private var dragProgress: Double = 0
    @State private var seekTarget: TimeInterval?

    init(
        currentTime: TimeInterval,
        duration: TimeInterval,
        onSeek: @escaping (TimeInterval) -> Void = { _ in }
    ) {
        self.currentTime = currentTime
        self.duration = duration
        self.onSeek = onSeek
    }

    private var progress: Double {
        guard duration > 0 else { return 0 }
        return min(currentTime / duration, 1.0)
    }

    /// True when actively dragging or waiting for seek to complete
    private var isInteracting: Bool {
        isDragging || seekTarget != nil
    }

    private var displayProgress: Double {
        isInteracting ? dragProgress : progress
    }

    private var displayTime: TimeInterval {
        isInteracting ? dragProgress * duration : currentTime
    }

    private var remainingTime: TimeInterval {
        duration - displayTime
    }

    private var trackBackground: Color {
        switch theme.textStyle {
        case .light: return .white.opacity(0.3)
        case .dark: return .black.opacity(0.2)
        }
    }

    private var trackFill: Color {
        switch theme.textStyle {
        case .light: return .white
        case .dark: return Color(white: 0.2)
        }
    }

    private var knobColor: Color {
        switch theme.textStyle {
        case .light: return .white
        case .dark: return Color(white: 0.15)
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            // Progress track with scrubbing
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track
                    Capsule()
                        .fill(trackBackground)
                        .frame(height: isInteracting ? 6 : 4)

                    // Filled track
                    Capsule()
                        .fill(trackFill)
                        .frame(width: max(0, geometry.size.width * displayProgress), height: isInteracting ? 6 : 4)

                    // Knob indicator (visible when interacting)
                    if isInteracting {
                        Circle()
                            .fill(knobColor)
                            .frame(width: 12, height: 12)
                            .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                            .position(
                                x: max(6, min(geometry.size.width - 6, geometry.size.width * displayProgress)),
                                y: 3
                            )
                    }
                }
                .frame(height: isInteracting ? 6 : 4)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if !isDragging {
                                isDragging = true
                                dragProgress = progress
                            }
                            let newProgress = value.location.x / geometry.size.width
                            dragProgress = min(max(newProgress, 0), 1)
                        }
                        .onEnded { _ in
                            let seekTime = dragProgress * duration
                            seekTarget = seekTime
                            onSeek(seekTime)
                            isDragging = false
                        }
                )
            }
            .frame(height: 12)
            .animation(.easeInOut(duration: 0.15), value: isInteracting)
            .onChange(of: currentTime) {
                // Clear seek target once playback catches up
                if let target = seekTarget, abs(currentTime - target) < 0.5 {
                    seekTarget = nil
                }
            }

            // Time labels
            HStack {
                Text(formatTime(displayTime))
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(theme.secondaryTextColor)

                Spacer()

                Text("-" + formatTime(remainingTime))
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(theme.secondaryTextColor)
            }
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        guard time.isFinite && time >= 0 else {
            return "--:--"
        }
        let totalSeconds = Int(time)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

#Preview("Light Text") {
    VStack(spacing: 40) {
        PlaybackProgressBar(currentTime: 78, duration: 242)
        PlaybackProgressBar(currentTime: 0, duration: 180)
        PlaybackProgressBar(currentTime: 0, duration: 0)
    }
    .padding(32)
    .background(ShuffleTheme.pink.bodyGradient)
    .environment(\.shuffleTheme, .pink)
}

#Preview("Dark Text") {
    VStack(spacing: 40) {
        PlaybackProgressBar(currentTime: 78, duration: 242)
        PlaybackProgressBar(currentTime: 0, duration: 180)
        PlaybackProgressBar(currentTime: 0, duration: 0)
    }
    .padding(32)
    .background(ShuffleTheme.silver.bodyGradient)
    .environment(\.shuffleTheme, .silver)
}
