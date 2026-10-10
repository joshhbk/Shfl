import Foundation

/// The shuffle algorithm a listener last chose, kept between launches under
/// the `shuffleAlgorithm` defaults key. The session draft is the only place
/// the algorithm is chosen; this only remembers it.
struct SavedShuffleAlgorithm {
    static let defaultsKey = "shuffleAlgorithm"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The saved algorithm, or `.noRepeat` when none was saved.
    func load() -> ShuffleAlgorithm {
        defaults.string(forKey: Self.defaultsKey).flatMap(ShuffleAlgorithm.init(rawValue:)) ?? .noRepeat
    }

    func save(_ algorithm: ShuffleAlgorithm) {
        defaults.set(algorithm.rawValue, forKey: Self.defaultsKey)
    }
}
