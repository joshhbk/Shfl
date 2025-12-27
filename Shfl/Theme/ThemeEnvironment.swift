import SwiftUI

private struct ShuffleThemeKey: EnvironmentKey {
    static let defaultValue: ShuffleTheme = .pink
}

extension EnvironmentValues {
    var shuffleTheme: ShuffleTheme {
        get { self[ShuffleThemeKey.self] }
        set { self[ShuffleThemeKey.self] = newValue }
    }
}
