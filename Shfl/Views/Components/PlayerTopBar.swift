import SwiftUI

/// Top bar with Add and Settings buttons for the player view
struct PlayerTopBar: View {
    @Environment(\.shuffleTheme) private var theme

    let onAddTapped: () -> Void
    let onSettingsTapped: () -> Void
    let topPadding: CGFloat

    var body: some View {
        HStack {
            Button(action: onAddTapped) {
                Image(systemName: "music.note.list")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(theme.bodyGradientTop)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .strokeBorder(.white.opacity(0.3), lineWidth: 1)
                    )
            }
            Spacer()
            Button(action: onSettingsTapped) {
                Image(systemName: "gearshape")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(theme.bodyGradientTop)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .strokeBorder(.white.opacity(0.3), lineWidth: 1)
                    )
            }
        }
        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
        .padding(.horizontal, 20)
        .padding(.top, topPadding)
    }
}
