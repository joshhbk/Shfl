import SwiftUI

/// Theme-independent colours from the design canvas, as light/dark pairs.
nonisolated enum Palette {
    static let content = ColorPair(light: .init(hex: 0xFFFFFF), dark: .init(hex: 0x222225))
    static let elevated = ColorPair(light: .init(hex: 0xFFFFFF), dark: .init(hex: 0x262629))
    static let pane = ColorPair(light: .init(hex: 0xF7F7F9), dark: .init(hex: 0x1E1E21))

    static let hairline = ColorPair(
        light: .init(hex: 0x000000, opacity: 0.10),
        dark: .init(hex: 0xFFFFFF, opacity: 0.12)
    )
    static let tileNeutral = ColorPair(light: .init(hex: 0xBDBDC3), dark: .init(hex: 0x5C5C63))
    static let traySlot = ColorPair(
        light: .init(hex: 0x000000, opacity: 0.08),
        dark: .init(hex: 0xFFFFFF, opacity: 0.10)
    )
    static let quietFill = ColorPair(
        light: .init(hex: 0x000000, opacity: 0.055),
        dark: .init(hex: 0xFFFFFF, opacity: 0.09)
    )

    static let textPrimary = ColorPair(light: .init(hex: 0x1D1D1F), dark: .init(hex: 0xF5F5F7))
    static let textSecondary = ColorPair(light: .init(hex: 0x55555C), dark: .init(hex: 0xADADB6))
    static let textTertiary = ColorPair(light: .init(hex: 0x63636B), dark: .init(hex: 0x94949E))

    static let wheel = ColorPair(light: .init(hex: 0x161617), dark: .init(hex: 0x0B0B0C))
    static let wheelGlyph = ColorPair(.init(hex: 0xD9D9DE))


    static let artworkPlaceholder = ColorPair(.init(hex: 0x2A2A2C))
    static let artworkPlaceholderGlyph = ColorPair(.init(hex: 0x8E8E94))

    static let onAccent = ColorPair(.init(hex: 0xFFFFFF))

    /// Backgrounds for `MonogramArtwork`, each dark enough for white initials.
    static let monograms: [Color.Resolved] = [
        .init(hex: 0xA8232E), .init(hex: 0x2B5FC0), .init(hex: 0x25703C),
        .init(hex: 0xA64508), .init(hex: 0x7B3FA0), .init(hex: 0x3F4753),
    ]
}
