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
        let page = try await musicService.fetchLibrarySongs(
            sortedBy: .recentlyAdded,
            limit: fetchLimit,
            offset: 0
        )

        // Filter out excluded songs
        let available = page.songs.filter { !excluding.contains($0.id) }

        // Apply algorithm
        switch algorithm {
        case .random:
            return Array(available.shuffled().prefix(limit))
        case .recentlyAdded:
            return Array(available.prefix(limit))
        }
    }
}
