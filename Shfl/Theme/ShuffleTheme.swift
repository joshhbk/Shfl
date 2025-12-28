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

    static let blue = ShuffleTheme(
        id: "blue",
        name: "Blue",
        bodyGradientTop: Color(red: 0.18, green: 0.58, blue: 0.96),
        bodyGradientBottom: Color(red: 0.12, green: 0.46, blue: 0.82),
        wheelStyle: .light,
        textStyle: .light,
        brushedMetalIntensity: 1.0,
        motionEnabled: true,
        motionSensitivity: 1.0
    )

    static let green = ShuffleTheme(
        id: "green",
        name: "Green",
        bodyGradientTop: Color(red: 0.30, green: 0.78, blue: 0.25),
        bodyGradientBottom: Color(red: 0.22, green: 0.66, blue: 0.18),
        wheelStyle: .light,
        textStyle: .light,
        brushedMetalIntensity: 1.0,
        motionEnabled: true,
        motionSensitivity: 1.0
    )

    static let orange = ShuffleTheme(
        id: "orange",
        name: "Orange",
        bodyGradientTop: Color(red: 0.98, green: 0.55, blue: 0.05),
        bodyGradientBottom: Color(red: 0.88, green: 0.44, blue: 0.02),
        wheelStyle: .light,
        textStyle: .light,
        brushedMetalIntensity: 1.0,
        motionEnabled: true,
        motionSensitivity: 1.0
    )

    static let pink = ShuffleTheme(
        id: "pink",
        name: "Pink",
        bodyGradientTop: Color(red: 0.96, green: 0.26, blue: 0.48),
        bodyGradientBottom: Color(red: 0.84, green: 0.18, blue: 0.40),
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
