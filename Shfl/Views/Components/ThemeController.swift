import SwiftUI

/// Manages theme switching with swipe gesture support
@Observable @MainActor
final class ThemeController {
    private(set) var currentThemeIndex: Int
    private(set) var dragOffset: CGFloat = 0

    private let swipeThreshold: CGFloat = 100

    var currentTheme: ShuffleTheme {
        ShuffleTheme.allThemes[currentThemeIndex]
    }

    init(startingIndex: Int? = nil) {
        self.currentThemeIndex = startingIndex ?? Int.random(in: 0..<ShuffleTheme.allThemes.count)
    }

    /// Initialize with a theme ID, falling back to random if not found
    init(themeId: String?) {
        if let id = themeId,
           let index = ShuffleTheme.allThemes.firstIndex(where: { $0.id == id }) {
            self.currentThemeIndex = index
        } else {
            self.currentThemeIndex = Int.random(in: 0..<ShuffleTheme.allThemes.count)
        }
    }

    func makeSwipeGesture() -> some Gesture {
        DragGesture(minimumDistance: 30)
            .onChanged { [weak self] value in
                guard let self else { return }
                let translation = value.translation.width
                // Add rubber-band resistance at edges
                if (self.currentThemeIndex == 0 && translation > 0) ||
                   (self.currentThemeIndex == ShuffleTheme.allThemes.count - 1 && translation < 0) {
                    self.dragOffset = translation * 0.3 // Resistance
                } else {
                    self.dragOffset = translation
                }
            }
            .onEnded { [weak self] value in
                guard let self else { return }
                let translation = value.translation.width
                let velocity = value.predictedEndTranslation.width

                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                    if translation < -self.swipeThreshold || velocity < -500 {
                        // Swipe left - next theme
                        if self.currentThemeIndex < ShuffleTheme.allThemes.count - 1 {
                            self.currentThemeIndex += 1
                            HapticFeedback.light.trigger()
                        } else {
                            HapticFeedback.light.trigger() // Boundary bump
                        }
                    } else if translation > self.swipeThreshold || velocity > 500 {
                        // Swipe right - previous theme
                        if self.currentThemeIndex > 0 {
                            self.currentThemeIndex -= 1
                            HapticFeedback.light.trigger()
                        } else {
                            HapticFeedback.light.trigger() // Boundary bump
                        }
                    }
                    self.dragOffset = 0
                }
            }
    }
}
