import Foundation

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
