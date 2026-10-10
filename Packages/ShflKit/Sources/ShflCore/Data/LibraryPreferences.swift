import Foundation

/// How the listener likes to browse and fill from their library: the song
/// sort order and the autofill algorithm. Each change is saved to
/// UserDefaults straight away.
@Observable
@MainActor
public final class LibraryPreferences {
    deinit {} // Keep nonisolated: Xcode 27 synthesizes an isolated one that can crash on release. See ViewTeardownTests.
    @ObservationIgnored private let defaults: UserDefaults

    var sortOption: SortOption {
        didSet {
            guard sortOption != oldValue else { return }
            defaults.set(sortOption.rawValue, forKey: "librarySortOption")
        }
    }

    public var autofillAlgorithm: AutofillAlgorithm {
        didSet {
            guard autofillAlgorithm != oldValue else { return }
            defaults.set(autofillAlgorithm.rawValue, forKey: "autofillAlgorithm")
        }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let sortRaw = defaults.string(forKey: "librarySortOption") ?? SortOption.mostPlayed.rawValue
        self.sortOption = SortOption(rawValue: sortRaw) ?? .mostPlayed

        let autofillRaw = defaults.string(forKey: "autofillAlgorithm") ?? AutofillAlgorithm.random.rawValue
        self.autofillAlgorithm = AutofillAlgorithm(rawValue: autofillRaw) ?? .random
    }
}
