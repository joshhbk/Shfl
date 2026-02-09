import SwiftUI

/// Computes album-aware theme colors by blending album art colors with the selected theme
@Observable
@MainActor
final class TintedThemeProvider {
    /// The computed theme with blended colors, ready for environment injection
    private(set) var computedTheme: ShuffleTheme

    /// The base theme before tinting (for reference)
    private var baseTheme: ShuffleTheme

    /// Tracks whether we have ever had an album color — first tint uses a longer animation
    private var hasHadAlbumColor = false

    init() {
        // Start with a default silver theme; will be updated immediately on appear
        let defaultTheme = ShuffleTheme(
            id: "silver",
            name: "Silver",
            bodyGradientTop: Color(red: 0.58, green: 0.58, blue: 0.60),
            bodyGradientBottom: Color(red: 0.48, green: 0.48, blue: 0.50),
            wheelStyle: .dark,
            textStyle: .dark,
            centerButtonIconColor: .black,
            brushedMetalIntensity: 1.0
        )
        self.baseTheme = defaultTheme
        self.computedTheme = defaultTheme
    }

    /// Update the computed theme by blending album color with the current theme
    ///
    /// - Parameters:
    ///   - albumColor: The dominant color from album artwork, or nil to use pure theme
    ///   - theme: The base theme to tint toward
    func update(albumColor: Color?, theme: ShuffleTheme) {
        baseTheme = theme

        guard let albumColor else {
            // No album color - use pure theme
            hasHadAlbumColor = false
            withAnimation(.easeInOut(duration: 0.3)) {
                computedTheme = theme
            }
            return
        }

        // Use album color directly — vibrancy scoring already selects a good candidate
        let derivedTop = albumColor
        let derivedBottom = ColorBlending.darken(albumColor, by: 0.12)

        // Determine wheel/text styles based on derived color luminance
        let (wheelStyle, textStyle, iconColor) = ColorBlending.determineStyles(for: derivedTop)

        // First tint (e.g. from empty/idle → playing) uses a longer, gentler animation
        // so the color wash feels intentional rather than a sudden shift
        let duration: Double = hasHadAlbumColor ? 0.3 : 0.8
        hasHadAlbumColor = true

        withAnimation(.easeInOut(duration: duration)) {
            computedTheme = ShuffleTheme(
                id: theme.id,
                name: theme.name,
                bodyGradientTop: derivedTop,
                bodyGradientBottom: derivedBottom,
                wheelStyle: wheelStyle,
                textStyle: textStyle,
                centerButtonIconColor: iconColor,
                brushedMetalIntensity: theme.brushedMetalIntensity
            )
        }
    }

}
