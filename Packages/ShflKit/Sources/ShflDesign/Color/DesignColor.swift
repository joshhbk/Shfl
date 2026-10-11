import SwiftUI

/// A design token that resolves against the current colour scheme, contrast setting, theme and artwork tint.
public nonisolated struct DesignColor: ShapeStyle, Hashable, Sendable {
    enum Role: Hashable, Sendable {
        case fixed(ColorPair)
        case accent
        case accentText
        case playerBody
        case ink
        case inkSecondary
        case hairline
    }

    let role: Role

    public func resolve(in environment: EnvironmentValues) -> Color.Resolved {
        let scheme = environment.colorScheme
        let theme = environment.shflTheme
        let increasedContrast = environment.colorSchemeContrast == .increased
        switch role {
        case .fixed(let pair):
            return pair.resolved(for: scheme)
        case .accent:
            return theme.accent.resolved(for: scheme)
        case .accentText:
            return theme.accentText.resolved(for: scheme)
        case .playerBody:
            let body = theme.body.resolved(for: scheme)
            guard let tone = environment.artworkTone, !increasedContrast else { return body }
            return ColorMath.mix(body, with: tone, share: theme.tintShare)
        case .ink:
            return theme.ink.resolved(for: scheme)
        case .inkSecondary:
            let ink = theme.ink.resolved(for: scheme)
            guard !increasedContrast else { return ink }
            let body = DesignColor.playerBody.resolve(in: environment)
            return ColorMath.quietest(ink, on: body, from: 0.84)
        case .hairline:
            let pair = increasedContrast ? Palette.textTertiary : Palette.hairline
            return pair.resolved(for: scheme)
        }
    }
}

nonisolated extension ShapeStyle where Self == DesignColor {
    /// Popovers, menus and settings panels.
    public static var surfaceElevated: DesignColor { .init(role: .fixed(Palette.elevated)) }

    public static var hairline: DesignColor { .init(role: .hairline) }
    public static var quietFill: DesignColor { .init(role: .fixed(Palette.quietFill)) }

    public static var textPrimary: DesignColor { .init(role: .fixed(Palette.textPrimary)) }
    public static var textSecondary: DesignColor { .init(role: .fixed(Palette.textSecondary)) }
    public static var textTertiary: DesignColor { .init(role: .fixed(Palette.textTertiary)) }


    /// Fills: selected rows, primary buttons, tray tiles.
    public static var accentFill: DesignColor { .init(role: .accent) }
    /// The theme colour adjusted to hold 4.5:1 as text on content surfaces.
    public static var accentText: DesignColor { .init(role: .accentText) }
    public static var onAccent: DesignColor { .init(role: .fixed(Palette.onAccent)) }

    /// The player's background: the theme body, tinted by `artworkTint(_:)` unless Increase Contrast is on.
    public static var playerBody: DesignColor { .init(role: .playerBody) }
    /// Text and glyphs on `playerBody`.
    public static var ink: DesignColor { .init(role: .ink) }
    public static var inkSecondary: DesignColor { .init(role: .inkSecondary) }

    public static var wheel: DesignColor { .init(role: .fixed(Palette.wheel)) }
    public static var wheelGlyph: DesignColor { .init(role: .fixed(Palette.wheelGlyph)) }

    /// The dark capsule behind toolbar pills and the mini player's session panel, in every theme.
    public static var chrome: DesignColor { .init(role: .fixed(Palette.chrome)) }
    public static var chromeGlyph: DesignColor { .init(role: .fixed(Palette.chromeGlyph)) }

    public static var artworkPlaceholder: DesignColor { .init(role: .fixed(Palette.artworkPlaceholder)) }
    public static var artworkPlaceholderGlyph: DesignColor { .init(role: .fixed(Palette.artworkPlaceholderGlyph)) }
}
