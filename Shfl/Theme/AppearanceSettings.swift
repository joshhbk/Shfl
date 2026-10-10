import Foundation

@Observable
@MainActor
final class AppearanceSettings {
    deinit {} // Keep nonisolated: Xcode 27 synthesizes an isolated one that can crash on release. See ViewTeardownTests.
    @ObservationIgnored private let defaults: UserDefaults

    var currentThemeId: String {
        didSet {
            guard currentThemeId != oldValue else { return }
            defaults.set(currentThemeId, forKey: "currentThemeId")
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.currentThemeId = defaults.string(forKey: "currentThemeId")
            ?? ShuffleTheme.allThemes.randomElement()?.id
            ?? "pink"
    }
}
