import SwiftUI

/// iPod Shuffle style metallic body container - extends edge to edge
struct ShuffleBodyView<Content: View>: View {
    @Environment(\.shuffleTheme) private var theme

    var height: CGFloat = 200
    @ViewBuilder let content: () -> Content

    private let cornerRadius: CGFloat = 20

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Body
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(theme.bodyGradientTop)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))

                // Subtle edge highlight
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.3), .clear, .black.opacity(0.1)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )

                // Content (click wheel)
                content()
            }
        }
        .frame(height: height)
        .shadow(color: .black.opacity(0.3), radius: 16, x: 0, y: 8)
    }
}

#Preview("Silver") {
    ZStack {
        Color.gray.ignoresSafeArea()

        VStack {
            Spacer()
            ShuffleBodyView {
                Circle()
                    .fill(.white)
                    .frame(width: 150, height: 150)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 50)
        }
    }
    .environment(\.shuffleTheme, .silver)
}

#Preview("Blue") {
    ZStack {
        Color.gray.ignoresSafeArea()

        VStack {
            Spacer()
            ShuffleBodyView {
                Circle()
                    .fill(.white)
                    .frame(width: 150, height: 150)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 50)
        }
    }
    .environment(\.shuffleTheme, .blue)
}
