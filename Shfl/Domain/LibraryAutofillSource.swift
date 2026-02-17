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
        switch algorithm {
        case .recentlyAdded:
            let fetchLimit = min(excluding.count + limit * 3, 500)
            let page = try await musicService.fetchLibrarySongs(
                sortedBy: .recentlyAdded, limit: fetchLimit, offset: 0
            )
            let available = page.songs.filter { !excluding.contains($0.id) }
            return Array(available.shuffled().prefix(limit))

        case .random:
            var allSongs: [Song] = []
            var offset = 0
            let pageSize = 500
            while true {
                let page = try await musicService.fetchLibrarySongs(
                    sortedBy: .alphabetical, limit: pageSize, offset: offset
                )
                allSongs.append(contentsOf: page.songs)
                guard page.hasMore else { break }
                offset += pageSize
            }
            let available = allSongs.filter { !excluding.contains($0.id) }
            return Array(available.shuffled().prefix(limit))
        }
    }
}
