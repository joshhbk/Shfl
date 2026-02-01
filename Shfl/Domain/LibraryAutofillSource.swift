import Foundation

/// AutofillSource implementation that fetches songs from the user's Apple Music library
struct LibraryAutofillSource: AutofillSource {
    private let musicService: MusicService
    private let algorithm: AutofillAlgorithm

    init(musicService: MusicService, algorithm: AutofillAlgorithm = .random) {
        self.musicService = musicService
        self.algorithm = algorithm
    }

    func fetchSongs(excluding: Set<String>, limit: Int) async throws -> [Song] {
        // Fetch enough to account for exclusions - need at least excluded count + desired limit
        let fetchLimit = min(excluding.count + limit * 3, 500)
        print("🔍 Autofill.fetchSongs: Fetching \(fetchLimit) songs from library...")

        let page = try await musicService.fetchLibrarySongs(
            sortedBy: .recentlyAdded,
            limit: fetchLimit,
            offset: 0
        )
        print("🔍 Autofill.fetchSongs: Got \(page.songs.count) songs from library")

        // Filter out excluded songs
        let available = page.songs.filter { !excluding.contains($0.id) }
        print("🔍 Autofill.fetchSongs: \(available.count) available after excluding \(excluding.count)")

        // Both algorithms shuffle - the difference is the source pool
        // (Currently both use recentlyAdded, but Random could use a different sort later)
        return Array(available.shuffled().prefix(limit))
    }
}
