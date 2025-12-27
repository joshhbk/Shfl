import SwiftUI

struct PlaybackProgressBar: View {
    let currentTime: TimeInterval
    let duration: TimeInterval

    private var progress: Double {
        guard duration > 0 else { return 0 }
        return min(currentTime / duration, 1.0)
    }

    var body: some View {
        VStack(spacing: 8) {
            // Progress track
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track
                    Capsule()
                        .fill(Color.white.opacity(0.3))
                        .frame(height: 4)

                    // Filled track
                    Capsule()
                        .fill(Color.white)
                        .frame(width: geometry.size.width * progress, height: 4)
                }
            }
            .frame(height: 4)

            // Time labels
            HStack {
                Text(formatTime(currentTime))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))

                Spacer()

                Text(formatTime(duration))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
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

#Preview {
    VStack(spacing: 40) {
        PlaybackProgressBar(currentTime: 78, duration: 242)
        PlaybackProgressBar(currentTime: 0, duration: 180)
        PlaybackProgressBar(currentTime: 0, duration: 0)
    }
    .padding(32)
    .background(Color(red: 0.8, green: 0.2, blue: 0.3))
}
