import SwiftUI

struct SkeletonSongRow: View {
    let animate: Bool

    init(animate: Bool = true) {
        self.animate = animate
    }

    @State private var shimmerOffset: CGFloat = -200

    var body: some View {
        HStack(spacing: 12) {
            // Album art placeholder
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.gray.opacity(0.2))
                .frame(width: 48, height: 48)
                .overlay(shimmerOverlay)

            VStack(alignment: .leading, spacing: 6) {
                // Title placeholder
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 140, height: 14)
                    .overlay(shimmerOverlay)

                // Artist placeholder
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 100, height: 12)
                    .overlay(shimmerOverlay)
            }

            Spacer()

            // Checkbox placeholder
            Circle()
                .fill(Color.gray.opacity(0.2))
                .frame(width: 22, height: 22)
                .overlay(shimmerOverlay)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .onAppear {
            guard animate else { return }
            withAnimation(
                .linear(duration: 1.5)
                .repeatForever(autoreverses: false)
            ) {
                shimmerOffset = 200
            }
        }
    }

    @ViewBuilder
    private var shimmerOverlay: some View {
        if animate {
            LinearGradient(
                colors: [
                    .clear,
                    .white.opacity(0.4),
                    .clear
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .offset(x: shimmerOffset)
            .clipped()
        }
    }
}

#Preview {
    VStack(spacing: 0) {
        SkeletonSongRow()
        Divider().padding(.leading, 72)
        SkeletonSongRow()
        Divider().padding(.leading, 72)
        SkeletonSongRow()
    }
}
