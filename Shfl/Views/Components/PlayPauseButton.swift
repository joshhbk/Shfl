import SwiftUI

struct PlayPauseButton: View {
    let isPlaying: Bool
    let action: () -> Void
    var wheelStyle: ShuffleTheme.WheelStyle = .light

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
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(buttonBackgroundColor)
                    .frame(width: 80, height: 80)
                    .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)

                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(iconColor)
                    .offset(x: isPlaying ? 0 : 2)
            }
        }
        .buttonStyle(.plain)
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
