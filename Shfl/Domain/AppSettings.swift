import Foundation
import SwiftUI

/// Centralized app settings using @Observable for automatic SwiftUI updates.
/// Replaces NotificationCenter-based communication for settings changes.
@Observable
@MainActor
final class AppSettings {
    @ObservationIgnored private let defaults: UserDefaults

    var shuffleAlgorithm: ShuffleAlgorithm {
        didSet {
            guard shuffleAlgorithm != oldValue else { return }
            defaults.set(shuffleAlgorithm.rawValue, forKey: "shuffleAlgorithm")
        }
    }

    var librarySortOption: SortOption {
        didSet {
            guard librarySortOption != oldValue else { return }
            defaults.set(librarySortOption.rawValue, forKey: "librarySortOption")
        }
    }

    var currentThemeId: String {
        didSet {
            guard currentThemeId != oldValue else { return }
            defaults.set(currentThemeId, forKey: "currentThemeId")
        }
    }

    var autofillAlgorithm: AutofillAlgorithm {
        didSet {
            guard autofillAlgorithm != oldValue else { return }
            defaults.set(autofillAlgorithm.rawValue, forKey: "autofillAlgorithm")
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let algorithmRaw = defaults.string(forKey: "shuffleAlgorithm") ?? ShuffleAlgorithm.noRepeat.rawValue
        self.shuffleAlgorithm = ShuffleAlgorithm(rawValue: algorithmRaw) ?? .noRepeat

        let sortRaw = defaults.string(forKey: "librarySortOption") ?? SortOption.mostPlayed.rawValue
        self.librarySortOption = SortOption(rawValue: sortRaw) ?? .mostPlayed

        self.currentThemeId = defaults.string(forKey: "currentThemeId")
            ?? ShuffleTheme.allThemes.randomElement()?.id
            ?? "pink"

        let autofillRaw = defaults.string(forKey: "autofillAlgorithm") ?? AutofillAlgorithm.random.rawValue
        self.autofillAlgorithm = AutofillAlgorithm(rawValue: autofillRaw) ?? .random
    }
}

// MARK: - Environment Keys

private struct AppSettingsKey: EnvironmentKey {
    static let defaultValue: AppSettings? = nil
}

private struct ShufflePlayerKey: EnvironmentKey {
    static let defaultValue: ShufflePlayer? = nil
}

private struct LastFMTransportKey: EnvironmentKey {
    static let defaultValue: LastFMTransport? = nil
}

extension EnvironmentValues {
    var appSettings: AppSettings? {
        get { self[AppSettingsKey.self] }
        set { self[AppSettingsKey.self] = newValue }
    }

    var shufflePlayer: ShufflePlayer? {
        get { self[ShufflePlayerKey.self] }
        set { self[ShufflePlayerKey.self] = newValue }
    }

    var lastFMTransport: LastFMTransport? {
        get { self[LastFMTransportKey.self] }
        set { self[LastFMTransportKey.self] = newValue }
    }
}
