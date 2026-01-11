import SwiftUI

/// A frosted glass panel with rounded corners
struct FrostedPanel<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
            )
            .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

#Preview {
    ZStack {
        LinearGradient(
            colors: [.purple, .blue],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()

        FrostedPanel {
            VStack(spacing: 4) {
                Text("Song Title")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Artist Name")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
        .padding(.horizontal, 20)
    }
}
