import SwiftUI

struct ShuffleTheme: Identifiable, Equatable {
    let id: String
    let name: String
    let bodyGradientTop: Color
    let bodyGradientBottom: Color
    let wheelStyle: WheelStyle
    let textStyle: TextStyle
    let centerButtonIconColor: Color

    enum WheelStyle: Equatable {
        case light
        case dark
    }

    enum TextStyle: Equatable {
        case light
        case dark
    }

    var bodyGradient: LinearGradient {
        LinearGradient(
            colors: [bodyGradientTop, bodyGradientBottom],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    var textColor: Color {
        switch textStyle {
        case .light: return .white
        case .dark: return Color(white: 0.15)
        }
    }

    var secondaryTextColor: Color {
        switch textStyle {
        case .light: return .white.opacity(0.8)
        case .dark: return Color(white: 0.15).opacity(0.7)
        }
    }

    /// The accent color derived from this theme, for use as app-wide tint
    var accentColor: Color {
        bodyGradientTop
    }
}

// MARK: - Theme Definitions

extension ShuffleTheme {
    // iPod Shuffle 4th gen: polished aluminum (darker, more realistic)
    static let silver = ShuffleTheme(
        id: "silver",
        name: "Silver",
        bodyGradientTop: Color(red: 0.58, green: 0.58, blue: 0.60),    // #949499 - medium aluminum
        bodyGradientBottom: Color(red: 0.48, green: 0.48, blue: 0.50), // #7A7A80 - darker aluminum
        wheelStyle: .dark,
        textStyle: .dark,
        centerButtonIconColor: .black
    )

    // iPod Shuffle 4th gen: #0094E1 "Blue Cola"
    static let blue = ShuffleTheme(
        id: "blue",
        name: "Blue",
        bodyGradientTop: Color(red: 0.00, green: 0.58, blue: 0.88),    // #0094E1 - iPod blue
        bodyGradientBottom: Color(red: 0.00, green: 0.48, blue: 0.78), // #007AC7 - slightly deeper
        wheelStyle: .light,
        textStyle: .light,
        centerButtonIconColor: .white
    )

    // iPod Shuffle 4th gen: #A0CB3B "Android Green"
    static let green = ShuffleTheme(
        id: "green",
        name: "Green",
        bodyGradientTop: Color(red: 0.63, green: 0.80, blue: 0.23),    // #A0CC3B - iPod green
        bodyGradientBottom: Color(red: 0.53, green: 0.70, blue: 0.16), // #87B329 - slightly deeper
        wheelStyle: .light,
        textStyle: .light,
        centerButtonIconColor: .white
    )

    // iPod Shuffle 4th gen: #FAB71F "Orange-Yellow"
    static let orange = ShuffleTheme(
        id: "orange",
        name: "Orange",
        bodyGradientTop: Color(red: 0.98, green: 0.72, blue: 0.12),    // #FAB81F - iPod orange
        bodyGradientBottom: Color(red: 0.90, green: 0.62, blue: 0.05), // #E69E0D - slightly deeper
        wheelStyle: .light,
        textStyle: .light,
        centerButtonIconColor: .white
    )

    // iPod Shuffle 4th gen: #EC5298 "Raspberry Pink"
    static let pink = ShuffleTheme(
        id: "pink",
        name: "Pink",
        bodyGradientTop: Color(red: 0.93, green: 0.32, blue: 0.60),    // #ED5299 - iPod pink
        bodyGradientBottom: Color(red: 0.83, green: 0.24, blue: 0.50), // #D43D80 - slightly deeper
        wheelStyle: .light,
        textStyle: .light,
        centerButtonIconColor: .white
    )

    static let allThemes: [ShuffleTheme] = [.silver, .blue, .green, .orange, .pink]

    static func random() -> ShuffleTheme {
        allThemes.randomElement() ?? .pink
    }

    /// Look up theme by ID for widget extension usage
    static func theme(byId id: String) -> ShuffleTheme? {
        allThemes.first { $0.id == id }
    }
}
