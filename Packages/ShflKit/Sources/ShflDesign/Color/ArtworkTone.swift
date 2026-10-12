import SwiftUI

public nonisolated enum ArtworkTone {
    /// The artwork's darkest strong colour, or nil when it has only greys.
    public static func pick(from colors: [Color.Resolved]) -> Color.Resolved? {
        colors
            .filter { ColorMath.chroma($0) >= minimumChroma }
            .min { ColorMath.luminance($0) < ColorMath.luminance($1) }
    }

    /// A tray tile's colour: an average that leans on the saturated, reasonably bright colours, or the plain
    /// average when there are none (greys, black, white). Nil for no colours.
    public static func tile(from colors: [Color.Resolved]) -> Color.Resolved? {
        guard !colors.isEmpty else { return nil }
        var weighted = SIMD3<Float>.zero
        var plain = SIMD3<Float>.zero
        var weight: Float = 0
        for color in colors {
            let rgb = SIMD3(color.red, color.green, color.blue)
            let high = rgb.max()
            let saturation = high > 0.001 ? (high - rgb.min()) / high : 0
            let w = saturation * saturation * smoothstep(0.15, 0.5, high)
            weighted += rgb * w
            weight += w
            plain += rgb
        }
        plain /= Float(colors.count)
        let vivid = weight > 0.0001 ? weighted / weight : plain
        let confidence = smoothstep(0.01, 0.06, weight / Float(colors.count))
        let mixed = plain + (vivid - plain) * confidence
        return Color.Resolved(red: mixed.x, green: mixed.y, blue: mixed.z)
    }

    private static func smoothstep(_ low: Float, _ high: Float, _ x: Float) -> Float {
        let t = min(max((x - low) / (high - low), 0), 1)
        return t * t * (3 - 2 * t)
    }

    static let minimumChroma: Float = 0.04
}
