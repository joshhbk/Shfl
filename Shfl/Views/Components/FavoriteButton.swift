import SwiftUI

struct FavoriteButton: View {
    @Environment(\.shuffleTheme) private var theme

    let isFavorite: Bool
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                        .tint(theme.textColor)
                } else {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(isFavorite ? .red : theme.secondaryTextColor)
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .frame(width: 44, height: 44)
        }
        .disabled(isLoading)
        .accessibilityLabel(isFavorite ? "Remove from favorites" : "Add to favorites")
    }
}

#Preview("Not Favorite") {
    FavoriteButton(isFavorite: false, isLoading: false, action: {})
        .padding()
        .background(ShuffleTheme.pink.bodyGradient)
        .environment(\.shuffleTheme, .pink)
}

#Preview("Favorite") {
    FavoriteButton(isFavorite: true, isLoading: false, action: {})
        .padding()
        .background(ShuffleTheme.pink.bodyGradient)
        .environment(\.shuffleTheme, .pink)
}

#Preview("Loading") {
    FavoriteButton(isFavorite: false, isLoading: true, action: {})
        .padding()
        .background(ShuffleTheme.silver.bodyGradient)
        .environment(\.shuffleTheme, .silver)
}
