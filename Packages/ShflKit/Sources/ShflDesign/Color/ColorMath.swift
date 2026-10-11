import Foundation
import SwiftUI

nonisolated enum ColorMath {
    /// Mixes in OKLab, matching CSS `color-mix(in oklab, …)` used by the design canvas.
    static func mix(_ base: Color.Resolved, with other: Color.Resolved, share: Float) -> Color.Resolved {
        let a = OKLab(base)
        let b = OKLab(other)
        let mixed = OKLab(
            l: a.l + (b.l - a.l) * share,
            a: a.a + (b.a - a.a) * share,
            b: a.b + (b.b - a.b) * share
        )
        return mixed.resolved(opacity: base.opacity)
    }

    /// Flattens a translucent colour onto an opaque background in gamma-encoded sRGB, as browsers do.
    static func composite(_ top: Color.Resolved, over bottom: Color.Resolved) -> Color.Resolved {
        let alpha = top.opacity
        return Color.Resolved(
            red: top.red * alpha + bottom.red * (1 - alpha),
            green: top.green * alpha + bottom.green * (1 - alpha),
            blue: top.blue * alpha + bottom.blue * (1 - alpha)
        )
    }

    static let minimumTextContrast = 4.5

    /// The lowest opacity at or above `opacity` that keeps `color` readable on `background`.
    static func quietest(_ color: Color.Resolved, on background: Color.Resolved, from opacity: Float) -> Color.Resolved {
        var opacity = opacity
        while opacity < 1, contrastRatio(color.opacity(opacity), on: background) < minimumTextContrast {
            opacity = min(opacity + 0.01, 1)
        }
        return color.opacity(opacity)
    }

    static func contrastRatio(_ foreground: Color.Resolved, on background: Color.Resolved) -> Double {
        let flattened = composite(foreground, over: background)
        let lighter = max(luminance(flattened), luminance(background))
        let darker = min(luminance(flattened), luminance(background))
        return (lighter + 0.05) / (darker + 0.05)
    }

    static func luminance(_ color: Color.Resolved) -> Double {
        0.2126 * Double(color.linearRed) + 0.7152 * Double(color.linearGreen) + 0.0722 * Double(color.linearBlue)
    }
}

nonisolated private struct OKLab {
    let l: Float
    let a: Float
    let b: Float

    init(l: Float, a: Float, b: Float) {
        self.l = l
        self.a = a
        self.b = b
    }

    init(_ color: Color.Resolved) {
        let r = color.linearRed, g = color.linearGreen, b = color.linearBlue
        let lms = (
            cbrtf(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b),
            cbrtf(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b),
            cbrtf(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        )
        l = 0.2104542553 * lms.0 + 0.7936177850 * lms.1 - 0.0040720468 * lms.2
        a = 1.9779984951 * lms.0 - 2.4285922050 * lms.1 + 0.4505937099 * lms.2
        self.b = 0.0259040371 * lms.0 + 0.7827717662 * lms.1 - 0.8086757660 * lms.2
    }

    func resolved(opacity: Float) -> Color.Resolved {
        let l1 = powf(l + 0.3963377774 * a + 0.2158037573 * b, 3)
        let m1 = powf(l - 0.1055613458 * a - 0.0638541728 * b, 3)
        let s1 = powf(l - 0.0894841775 * a - 1.2914855480 * b, 3)
        var resolved = Color.Resolved(red: 0, green: 0, blue: 0, opacity: opacity)
        resolved.linearRed = clamp(4.0767416621 * l1 - 3.3077115913 * m1 + 0.2309699292 * s1)
        resolved.linearGreen = clamp(-1.2684380046 * l1 + 2.6097574011 * m1 - 0.3413193965 * s1)
        resolved.linearBlue = clamp(-0.0041960863 * l1 - 0.7034186147 * m1 + 1.7076147010 * s1)
        return resolved
    }

    private func clamp(_ value: Float) -> Float {
        min(max(value, 0), 1)
    }
}
