import SwiftUI

nonisolated struct ColorPair: Hashable, Sendable {
    let light: Color.Resolved
    let dark: Color.Resolved

    init(light: Color.Resolved, dark: Color.Resolved) {
        self.light = light
        self.dark = dark
    }

    init(_ both: Color.Resolved) {
        self.init(light: both, dark: both)
    }

    func resolved(for scheme: ColorScheme) -> Color.Resolved {
        scheme == .dark ? dark : light
    }
}

nonisolated extension Color.Resolved {
    init(hex: UInt32, opacity: Float = 1) {
        self.init(
            red: Float((hex >> 16) & 0xFF) / 255,
            green: Float((hex >> 8) & 0xFF) / 255,
            blue: Float(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    func opacity(_ opacity: Float) -> Color.Resolved {
        Color.Resolved(red: red, green: green, blue: blue, opacity: self.opacity * opacity)
    }
}
