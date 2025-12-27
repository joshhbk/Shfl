import SwiftUI

struct PlaybackProgressBar: View {
    @Environment(\.shuffleTheme) private var theme

    let currentTime: TimeInterval
    let duration: TimeInterval

    private var progress: Double {
        guard duration > 0 else { return 0 }
        return min(currentTime / duration, 1.0)
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

    var body: some View {
        VStack(spacing: 8) {
            // Progress track
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track
                    Capsule()
                        .fill(trackBackground)
                        .frame(height: 4)

                    // Filled track
                    Capsule()
                        .fill(trackFill)
                        .frame(width: geometry.size.width * progress, height: 4)
                }
            }
            .frame(height: 4)

            // Time labels
            HStack {
                Text(formatTime(currentTime))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(theme.secondaryTextColor)

                Spacer()

                Text(formatTime(duration))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(theme.secondaryTextColor)
            }
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        guard time.isFinite && time >= 0 else {
            return "--:--"
        }
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
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
