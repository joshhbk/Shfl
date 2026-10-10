import Foundation

package struct SavedShuffleAlgorithm {
    static let defaultsKey = "shuffleAlgorithm"

    private let defaults: UserDefaults

    package init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    package func load() -> ShuffleAlgorithm {
        defaults.string(forKey: Self.defaultsKey).flatMap(ShuffleAlgorithm.init(rawValue:)) ?? SessionDraft.defaultAlgorithm
    }

    package func save(_ algorithm: ShuffleAlgorithm) {
        defaults.set(algorithm.rawValue, forKey: Self.defaultsKey)
    }
}
