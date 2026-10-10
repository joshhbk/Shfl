import Foundation

// PR 4 → package
public struct SavedShuffleAlgorithm {
    static let defaultsKey = "shuffleAlgorithm"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> ShuffleAlgorithm {
        defaults.string(forKey: Self.defaultsKey).flatMap(ShuffleAlgorithm.init(rawValue:)) ?? SessionDraft.defaultAlgorithm
    }

    public func save(_ algorithm: ShuffleAlgorithm) {
        defaults.set(algorithm.rawValue, forKey: Self.defaultsKey)
    }
}
