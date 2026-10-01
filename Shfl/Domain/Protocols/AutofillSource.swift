import Foundation

/// Algorithm options for autofill behavior
enum AutofillAlgorithm: String, CaseIterable, Sendable, Hashable {
    case random = "random"
    case recentlyAdded = "recentlyAdded"

    var displayName: String {
        switch self {
        case .random: return "Random"
        case .recentlyAdded: return "Recently Added"
        }
    }
}

/// Protocol for sources that can provide songs for autofill
/// Uses the strategy pattern to allow different sources (library, playlist) to provide songs
protocol AutofillSource: Sendable {
    /// Fetch random songs for autofill, excluding songs already in the shuffle
    /// - Parameters:
    ///   - excluding: Song IDs to exclude (already in shuffle)
    ///   - limit: Maximum number of songs to return
    /// - Returns: Array of songs to add
    func fetchSongs(excluding: Set<String>, limit: Int) async throws -> [Song]
}

/// An autofill source that can fetch ahead of time, so the next autofill
/// needn't wait for the library.
@MainActor
protocol WarmableAutofillSource: AutofillSource {
    /// Starts fetching songs for the next autofill, if not already doing so.
    func warm()
}
