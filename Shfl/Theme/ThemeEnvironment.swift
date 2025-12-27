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

private struct MotionManagerKey: EnvironmentKey {
    static let defaultValue: MotionManager? = nil
}

extension EnvironmentValues {
    var motionManager: MotionManager? {
        get { self[MotionManagerKey.self] }
        set { self[MotionManagerKey.self] = newValue }
    }
}
