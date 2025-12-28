import Foundation

/// AutofillSource implementation that fetches random songs from the user's Apple Music library
struct LibraryAutofillSource: AutofillSource {
    private let musicService: MusicService

    init(musicService: MusicService) {
        self.musicService = musicService
    }

    func fetchSongs(excluding: Set<String>, limit: Int) async throws -> [Song] {
        // Fetch enough to account for exclusions - need at least excluded count + desired limit
        let fetchLimit = min(excluding.count + limit * 3, 500)
        let page = try await musicService.fetchLibrarySongs(
            sortedBy: .recentlyAdded,
            limit: fetchLimit,
            offset: 0
        )

        // Filter out excluded songs and shuffle
        let available = page.songs.filter { !excluding.contains($0.id) }
        let shuffled = available.shuffled()

        // Return up to limit
        return Array(shuffled.prefix(limit))
    }
}
