import Foundation

/// The shuffle algorithm a listener last chose, kept between launches under
/// the `shuffleAlgorithm` defaults key. The session draft is the only place
/// the algorithm is chosen; this only remembers it.
public struct SavedShuffleAlgorithm {
    static let defaultsKey = "shuffleAlgorithm"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The saved algorithm, or the draft's default when none was saved.
    public func load() -> ShuffleAlgorithm {
        defaults.string(forKey: Self.defaultsKey).flatMap(ShuffleAlgorithm.init(rawValue:)) ?? SessionDraft.defaultAlgorithm
    }

    public func save(_ algorithm: ShuffleAlgorithm) {
        defaults.set(algorithm.rawValue, forKey: Self.defaultsKey)
    }
}
