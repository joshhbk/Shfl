import SwiftUI

struct ShuffleTheme: Identifiable, Equatable {
    let id: String
    let name: String
    let bodyGradientTop: Color
    let bodyGradientBottom: Color
    let wheelStyle: WheelStyle
    let textStyle: TextStyle
    let brushedMetalIntensity: CGFloat
    let motionEnabled: Bool
    let motionSensitivity: CGFloat

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
}

// MARK: - Theme Definitions

extension ShuffleTheme {
    static let silver = ShuffleTheme(
        id: "silver",
        name: "Silver",
        bodyGradientTop: Color(red: 0.75, green: 0.75, blue: 0.75),
        bodyGradientBottom: Color(red: 0.66, green: 0.66, blue: 0.66),
        wheelStyle: .dark,
        textStyle: .dark,
        brushedMetalIntensity: 1.0,
        motionEnabled: true,
        motionSensitivity: 1.0
    )

    // iPod Shuffle 4th gen: bright aqua blue
    static let blue = ShuffleTheme(
        id: "blue",
        name: "Blue",
        bodyGradientTop: Color(red: 0.00, green: 0.68, blue: 0.94),    // #00ADEF - bright cyan-blue
        bodyGradientBottom: Color(red: 0.00, green: 0.58, blue: 0.84), // #0094D6 - slightly deeper
        wheelStyle: .light,
        textStyle: .light,
        brushedMetalIntensity: 1.0,
        motionEnabled: true,
        motionSensitivity: 1.0
    )

    // iPod Shuffle 4th gen: vibrant lime green
    static let green = ShuffleTheme(
        id: "green",
        name: "Green",
        bodyGradientTop: Color(red: 0.55, green: 0.82, blue: 0.22),    // #8CD138 - bright lime
        bodyGradientBottom: Color(red: 0.45, green: 0.72, blue: 0.15), // #73B826 - slightly deeper
        wheelStyle: .light,
        textStyle: .light,
        brushedMetalIntensity: 1.0,
        motionEnabled: true,
        motionSensitivity: 1.0
    )

    // iPod Shuffle 4th gen: golden orange
    static let orange = ShuffleTheme(
        id: "orange",
        name: "Orange",
        bodyGradientTop: Color(red: 1.00, green: 0.62, blue: 0.04),    // #FF9E0A - bright golden orange
        bodyGradientBottom: Color(red: 0.95, green: 0.52, blue: 0.00), // #F28500 - slightly deeper
        wheelStyle: .light,
        textStyle: .light,
        brushedMetalIntensity: 1.0,
        motionEnabled: true,
        motionSensitivity: 1.0
    )

    // iPod Shuffle 4th gen: hot pink/magenta
    static let pink = ShuffleTheme(
        id: "pink",
        name: "Pink",
        bodyGradientTop: Color(red: 0.98, green: 0.22, blue: 0.55),    // #FA388C - hot pink
        bodyGradientBottom: Color(red: 0.88, green: 0.15, blue: 0.45), // #E02673 - slightly deeper
        wheelStyle: .light,
        textStyle: .light,
        brushedMetalIntensity: 1.0,
        motionEnabled: true,
        motionSensitivity: 1.0
    )

    static let allThemes: [ShuffleTheme] = [.silver, .blue, .green, .orange, .pink]

    static func random() -> ShuffleTheme {
        allThemes.randomElement() ?? .pink
    }
}
