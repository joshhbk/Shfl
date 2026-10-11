import SwiftUI

/// Theme-independent colours from the design canvas, as light/dark pairs.
nonisolated enum Palette {
    static let window = ColorPair(light: .init(hex: 0xF3F3F5), dark: .init(hex: 0x1B1B1D))
    static let content = ColorPair(light: .init(hex: 0xFFFFFF), dark: .init(hex: 0x222225))
    static let elevated = ColorPair(light: .init(hex: 0xFFFFFF), dark: .init(hex: 0x262629))
    static let sidebar = ColorPair(light: .init(hex: 0xE9E9ED), dark: .init(hex: 0x29292C))
    static let pane = ColorPair(light: .init(hex: 0xF7F7F9), dark: .init(hex: 0x1E1E21))

    static let hairline = ColorPair(
        light: .init(hex: 0x000000, opacity: 0.10),
        dark: .init(hex: 0xFFFFFF, opacity: 0.12)
    )
    static let quietFill = ColorPair(
        light: .init(hex: 0x000000, opacity: 0.055),
        dark: .init(hex: 0xFFFFFF, opacity: 0.09)
    )
    static let emptySlot = ColorPair(
        light: .init(hex: 0x000000, opacity: 0.08),
        dark: .init(hex: 0xFFFFFF, opacity: 0.10)
    )

    static let textPrimary = ColorPair(light: .init(hex: 0x1D1D1F), dark: .init(hex: 0xF5F5F7))
    static let textSecondary = ColorPair(light: .init(hex: 0x55555C), dark: .init(hex: 0xADADB6))
    static let textTertiary = ColorPair(light: .init(hex: 0x63636B), dark: .init(hex: 0x94949E))

    static let warning = ColorPair(light: .init(hex: 0xA8291F), dark: .init(hex: 0xFF8F80))
    static let success = ColorPair(light: .init(hex: 0x2E9E55), dark: .init(hex: 0x3FB56A))
    static let successText = ColorPair(light: .init(hex: 0x1D763C), dark: .init(hex: 0x6FD08C))

    static let wheel = ColorPair(light: .init(hex: 0x161617), dark: .init(hex: 0x0B0B0C))
    static let wheelGlyph = ColorPair(.init(hex: 0xD9D9DE))

    static let chrome = ColorPair(.init(hex: 0x1C1C1E))
    static let chromeGlyph = ColorPair(.init(hex: 0xE4E4E9))
    static let chromeText = ColorPair(.init(hex: 0xF2F2F5))
    static let chromeTextSecondary = ColorPair(.init(hex: 0xB4B4BC))

    static let artworkPlaceholder = ColorPair(.init(hex: 0x2A2A2C))
    static let artworkPlaceholderGlyph = ColorPair(.init(hex: 0x8E8E94))

    static let onAccent = ColorPair(.init(hex: 0xFFFFFF))
}
