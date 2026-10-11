import SwiftUI

/// One of the five iPod shuffle colours. Ids match the iOS `ShuffleTheme` presets so a saved choice carries over.
public nonisolated struct ShflTheme: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    let accent: ColorPair
    let accentText: ColorPair
    let body: ColorPair
    let ink: ColorPair
    /// How much of the artwork's tone mixes into the player body. Silver keeps less so dark ink holds 4.5:1.
    let tintShare: Float
}

nonisolated extension ShflTheme {
    public static let silver = ShflTheme(
        id: "silver",
        name: "Silver",
        accent: ColorPair(light: .init(hex: 0x4B5563), dark: .init(hex: 0x6B7280)),
        accentText: ColorPair(light: .init(hex: 0x3F4753), dark: .init(hex: 0xC5CAD3)),
        body: ColorPair(light: .init(hex: 0xA9A8AD), dark: .init(hex: 0x3A3C42)),
        ink: ColorPair(light: .init(hex: 0x1D1D1F), dark: .init(hex: 0xF5F5F7)),
        tintShare: 0.10
    )

    public static let blue = ShflTheme(
        id: "blue",
        name: "Blue",
        accent: ColorPair(light: .init(hex: 0x2B5FC0), dark: .init(hex: 0x356DD6)),
        accentText: ColorPair(light: .init(hex: 0x2B5FC0), dark: .init(hex: 0x8FB4FF)),
        body: ColorPair(light: .init(hex: 0x2B5FC0), dark: .init(hex: 0x1D3566)),
        ink: ColorPair(.init(hex: 0xFFFFFF)),
        tintShare: 0.24
    )

    public static let green = ShflTheme(
        id: "green",
        name: "Green",
        accent: ColorPair(light: .init(hex: 0x25703C), dark: .init(hex: 0x2B8048)),
        accentText: ColorPair(light: .init(hex: 0x25703C), dark: .init(hex: 0x7FD69A)),
        body: ColorPair(light: .init(hex: 0x2A7A43), dark: .init(hex: 0x1B4A2B)),
        ink: ColorPair(.init(hex: 0xFFFFFF)),
        tintShare: 0.24
    )

    public static let orange = ShflTheme(
        id: "orange",
        name: "Orange",
        accent: ColorPair(light: .init(hex: 0xB84E0B), dark: .init(hex: 0xBF540E)),
        accentText: ColorPair(light: .init(hex: 0xA64508), dark: .init(hex: 0xFFA869)),
        body: ColorPair(light: .init(hex: 0xBD520C), dark: .init(hex: 0x6E3410)),
        ink: ColorPair(.init(hex: 0xFFFFFF)),
        tintShare: 0.24
    )

    public static let pink = ShflTheme(
        id: "pink",
        name: "Pink",
        accent: ColorPair(light: .init(hex: 0xC2356F), dark: .init(hex: 0xC93A7C)),
        accentText: ColorPair(light: .init(hex: 0xB32C63), dark: .init(hex: 0xFF93BE)),
        body: ColorPair(light: .init(hex: 0xC93A7C), dark: .init(hex: 0x6B1F43)),
        ink: ColorPair(.init(hex: 0xFFFFFF)),
        tintShare: 0.24
    )

    public static let all: [ShflTheme] = [.silver, .blue, .green, .orange, .pink]

    public static func theme(id: String) -> ShflTheme? {
        all.first { $0.id == id }
    }
}
