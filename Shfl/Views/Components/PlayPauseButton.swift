import SwiftUI

struct PlayPauseButton: View {
    let isPlaying: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(.white)
                    .frame(width: 80, height: 80)
                    .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)

                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(.black)
                    .offset(x: isPlaying ? 0 : 2)
            }
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .medium), trigger: isPlaying)
    }
}

#Preview {
    VStack(spacing: 40) {
        PlayPauseButton(isPlaying: false) {}
        PlayPauseButton(isPlaying: true) {}
    }
    .padding()
    .background(Color.gray.opacity(0.2))
}
