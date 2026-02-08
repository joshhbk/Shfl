import SwiftUI
import UIKit

/// HSB color math utilities for theme tinting
enum ColorBlending {
    struct HSB {
        var hue: CGFloat
        var saturation: CGFloat
        var brightness: CGFloat

        func toColor() -> Color {
            Color(hue: hue, saturation: saturation, brightness: brightness)
        }
    }

    /// Extract HSB components from a SwiftUI Color
    static func extractHSB(from color: Color) -> HSB {
        let uiColor = UIColor(color)
        var h: CGFloat = 0
        var s: CGFloat = 0
        var b: CGFloat = 0
        uiColor.getHue(&h, saturation: &s, brightness: &b, alpha: nil)
        return HSB(hue: h, saturation: s, brightness: b)
    }

    /// Interpolate between two hues, handling circular wraparound (0.0 and 1.0 are both red)
    static func lerpHue(_ h1: CGFloat, _ h2: CGFloat, _ t: CGFloat) -> CGFloat {
        var delta = h2 - h1

        // Take the shortest path around the color wheel
        if delta > 0.5 { delta -= 1.0 }
        if delta < -0.5 { delta += 1.0 }

        var result = h1 + delta * t

        // Normalize to [0, 1)
        if result < 0 { result += 1.0 }
        if result >= 1.0 { result -= 1.0 }

        return result
    }

    /// Calculate relative luminance for contrast decisions (WCAG formula)
    static func relativeLuminance(of color: Color) -> CGFloat {
        let uiColor = UIColor(color)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: nil)

        // sRGB relative luminance
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    /// Blend an album color with a theme color, shifting the album's hue toward the theme
    ///
    /// - Parameters:
    ///   - albumColor: The dominant color extracted from album artwork
    ///   - themeColor: The reference color from the selected theme
    ///   - hueFactor: How much to shift toward theme hue (0 = album only, 1 = theme only). Default 0.35
    ///   - minSaturation: Minimum saturation to ensure vibrancy. Default 0.3
    ///   - maxSaturation: Maximum saturation to prevent harshness. Default 0.85
    ///   - minBrightness: Minimum brightness for readability. Default 0.4
    ///   - maxBrightness: Maximum brightness to avoid washed out. Default 0.8
    static func blend(
        albumColor: Color,
        themeColor: Color,
        hueFactor: CGFloat = 0.35,
        minSaturation: CGFloat = 0.3,
        maxSaturation: CGFloat = 0.85,
        minBrightness: CGFloat = 0.4,
        maxBrightness: CGFloat = 0.8
    ) -> Color {
        let album = extractHSB(from: albumColor)
        let theme = extractHSB(from: themeColor)

        let blendedHue = lerpHue(album.hue, theme.hue, hueFactor)

        // For very desaturated album colors, lean more toward theme saturation
        var blendedSaturation = album.saturation
        if album.saturation < 0.15 {
            blendedSaturation = album.saturation + (theme.saturation - album.saturation) * 0.5
        }
        blendedSaturation = min(max(blendedSaturation, minSaturation), maxSaturation)

        let blendedBrightness = min(max(album.brightness, minBrightness), maxBrightness)

        return Color(hue: blendedHue, saturation: blendedSaturation, brightness: blendedBrightness)
    }

    /// Create a darker variant for gradient bottom (reduces brightness by a percentage)
    static func darken(_ color: Color, by amount: CGFloat = 0.12) -> Color {
        let hsb = extractHSB(from: color)
        let darkerBrightness = max(hsb.brightness - amount, 0.2)
        return Color(hue: hsb.hue, saturation: hsb.saturation, brightness: darkerBrightness)
    }

    /// WCAG contrast ratio between two colors (returns value >= 1.0)
    static func contrastRatio(between foreground: Color, and background: Color) -> CGFloat {
        let fgLum = relativeLuminance(of: foreground)
        let bgLum = relativeLuminance(of: background)
        let lighter = max(fgLum, bgLum)
        let darker = min(fgLum, bgLum)
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// Determine appropriate wheel and text styles based on color luminance
    static func determineStyles(for color: Color) -> (wheel: ShuffleTheme.WheelStyle, text: ShuffleTheme.TextStyle, iconColor: Color) {
        let luminance = relativeLuminance(of: color)

        // Threshold around 0.5 - lighter colors need dark text/wheel for contrast
        if luminance > 0.45 {
            return (.dark, .dark, .black)
        } else {
            return (.light, .light, .white)
        }
    }
}
