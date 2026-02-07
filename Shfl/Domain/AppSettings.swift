import Foundation
import SwiftUI

/// Centralized app settings using @Observable for automatic SwiftUI updates.
/// Replaces NotificationCenter-based communication for settings changes.
@Observable
@MainActor
final class AppSettings {
    var shuffleAlgorithm: ShuffleAlgorithm {
        didSet {
            guard shuffleAlgorithm != oldValue else { return }
            UserDefaults.standard.set(shuffleAlgorithm.rawValue, forKey: "shuffleAlgorithm")
        }
    }

    var librarySortOption: SortOption {
        didSet {
            guard librarySortOption != oldValue else { return }
            UserDefaults.standard.set(librarySortOption.rawValue, forKey: "librarySortOption")
        }
    }

    var currentThemeId: String {
        didSet {
            guard currentThemeId != oldValue else { return }
            UserDefaults.standard.set(currentThemeId, forKey: "currentThemeId")
        }
    }

    init() {
        let algorithmRaw = UserDefaults.standard.string(forKey: "shuffleAlgorithm") ?? ShuffleAlgorithm.noRepeat.rawValue
        self.shuffleAlgorithm = ShuffleAlgorithm(rawValue: algorithmRaw) ?? .noRepeat

        let sortRaw = UserDefaults.standard.string(forKey: "librarySortOption") ?? SortOption.mostPlayed.rawValue
        self.librarySortOption = SortOption(rawValue: sortRaw) ?? .mostPlayed

        self.currentThemeId = UserDefaults.standard.string(forKey: "currentThemeId")
            ?? ShuffleTheme.allThemes.randomElement()?.id
            ?? "pink"
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
