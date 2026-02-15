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
        return min(max(currentTime / duration, 0), 1.0)
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
                let trackHeight: CGFloat = isInteracting ? 8 : 6
                let knobRadius: CGFloat = 7
                let rawFilledWidth = max(0, min(geometry.size.width, geometry.size.width * displayProgress))
                let minKnobX = min(knobRadius, geometry.size.width / 2)
                let maxKnobX = max(minKnobX, geometry.size.width - minKnobX)
                let knobX = min(max(rawFilledWidth, minKnobX), maxKnobX)
                let filledWidth = isInteracting ? knobX : rawFilledWidth

                ZStack(alignment: .leading) {
                    // Background track
                    Capsule()
                        .fill(trackBackground)
                        .frame(height: trackHeight)

                    // Filled track
                    Capsule()
                        .fill(trackFill)
                        .frame(width: filledWidth, height: trackHeight)

                    // Knob indicator (visible when interacting)
                    if isInteracting {
                        Circle()
                            .fill(knobColor)
                            .frame(width: 14, height: 14)
                            .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                            .position(
                                x: knobX,
                                y: trackHeight / 2
                            )
                    }
                }
                .frame(height: trackHeight)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if !isDragging {
                                isDragging = true
                                dragProgress = progress
                            }
                            guard geometry.size.width > 0 else { return }
                            let newProgress = value.location.x / geometry.size.width
                            dragProgress = min(max(newProgress, 0), 1)
                        }
                        .onEnded { _ in
                            guard duration > 0 else {
                                isDragging = false
                                seekTarget = nil
                                return
                            }
                            let seekTime = dragProgress * duration
                            seekTarget = seekTime
                            onSeek(seekTime)
                            isDragging = false
                        }
                )
            }
            .frame(height: 12)
            .animation(.easeInOut(duration: 0.15), value: isInteracting)
            .onChange(of: currentTime) { _, _ in
                // Clear seek target once playback catches up
                if let target = seekTarget, abs(currentTime - target) < 0.5 {
                    seekTarget = nil
                    dragProgress = progress
                }
            }

            // Time labels
            HStack {
                Text(formatTime(displayTime))
                    .font(.system(size: 12, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(theme.secondaryTextColor)

                Spacer()

                Text("-" + formatTime(remainingTime))
                    .font(.system(size: 12, weight: .medium, design: .rounded).monospacedDigit())
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

/// Wrapper that reads time/duration from PlayerProgressState directly,
/// isolating the timer-driven observation to this subtree only.
struct LivePlaybackProgressBar: View {
    var progressState: PlayerProgressState
    let onSeek: (TimeInterval) -> Void

    var body: some View {
        PlaybackProgressBar(
            currentTime: progressState.currentTime,
            duration: progressState.duration,
            onSeek: onSeek
        )
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
