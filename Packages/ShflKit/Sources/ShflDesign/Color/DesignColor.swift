import SwiftUI

/// A design token that resolves against the current colour scheme, contrast setting, theme and artwork tint.
public nonisolated struct DesignColor: ShapeStyle, Hashable, Sendable {
    indirect enum Role: Hashable, Sendable {
        case fixed(ColorPair)
        /// Turns `onAccent` on a selected list row.
        case selectable(Role, selectedOpacity: Float)
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
        case .selectable(let role, let selectedOpacity):
            guard environment.backgroundProminence == .increased else { return DesignColor(role: role).resolve(in: environment) }
            return Palette.onAccent.resolved(for: scheme).opacity(selectedOpacity)
        case .accent:
            return theme.accent.resolved(for: scheme)
        case .accentText:
            return theme.accentText.resolved(for: scheme)
        case .playerBody:
            let body = theme.body.resolved(for: scheme)
            guard let tone = environment.artworkTone, !increasedContrast else { return body }
            let tinted = ColorMath.mix(body, with: tone, share: theme.tintShare)
            let ink = theme.ink.resolved(for: scheme)
            let keepsInkReadable = ColorMath.contrastRatio(ink, on: tinted) >= ColorMath.minimumTextContrast
            return keepsInkReadable ? tinted : body
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
    /// Lists and the library's main column.
    public static var surfaceContent: DesignColor { .init(role: .fixed(Palette.content)) }
    /// Popovers, menus and settings panels.
    public static var surfaceElevated: DesignColor { .init(role: .fixed(Palette.elevated)) }
    /// The Picks column.
    public static var surfacePane: DesignColor { .init(role: .fixed(Palette.pane)) }
    /// An empty slot in the tray.
    public static var traySlot: DesignColor { .init(role: .fixed(Palette.traySlot)) }
    /// A picked song's tile when its artwork has no colour to give.
    public static var tileNeutral: DesignColor { .init(role: .fixed(Palette.tileNeutral)) }

    public static var hairline: DesignColor { .init(role: .hairline) }
    public static var quietFill: DesignColor { .init(role: .fixed(Palette.quietFill)) }

    public static var textPrimary: DesignColor { .init(role: .selectable(.fixed(Palette.textPrimary), selectedOpacity: 1)) }
    public static var textSecondary: DesignColor { .init(role: .selectable(.fixed(Palette.textSecondary), selectedOpacity: 1)) }
    public static var textTertiary: DesignColor { .init(role: .selectable(.fixed(Palette.textTertiary), selectedOpacity: 0.8)) }

    /// Fills: selected rows, primary buttons, tray tiles.
    public static var accentFill: DesignColor { .init(role: .accent) }
    /// The theme colour adjusted to hold 4.5:1 as text on content surfaces.
    public static var accentText: DesignColor { .init(role: .accentText) }
    public static var onAccent: DesignColor { .init(role: .fixed(Palette.onAccent)) }
    /// Text and outlines for something that didn't work, like a batch with no room.
    public static var warning: DesignColor { .init(role: .fixed(Palette.warning)) }
    /// `accentText` for marks inside list rows, like the playing glyph and the Next shuffle tag.
    public static var accentMark: DesignColor { .init(role: .selectable(.accentText, selectedOpacity: 1)) }

    /// The player's background: the theme body, tinted by `artworkTint(_:)` unless Increase Contrast is on.
    public static var playerBody: DesignColor { .init(role: .playerBody) }
    /// Text and glyphs on `playerBody`.
    public static var ink: DesignColor { .init(role: .ink) }
    public static var inkSecondary: DesignColor { .init(role: .inkSecondary) }

    public static var wheel: DesignColor { .init(role: .fixed(Palette.wheel)) }
    public static var wheelGlyph: DesignColor { .init(role: .fixed(Palette.wheelGlyph)) }


    public static var artworkPlaceholder: DesignColor { .init(role: .fixed(Palette.artworkPlaceholder)) }
    public static var artworkPlaceholderGlyph: DesignColor { .init(role: .fixed(Palette.artworkPlaceholderGlyph)) }
}
