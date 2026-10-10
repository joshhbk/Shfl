import Foundation

/// AutofillSource implementation that fetches songs from the user's Apple Music library
nonisolated struct LibraryAutofillSource: AutofillSource {
    private let libraryCatalog: LibraryCatalog
    private let algorithm: AutofillAlgorithm

    init(libraryCatalog: LibraryCatalog, algorithm: AutofillAlgorithm = .random) {
        self.libraryCatalog = libraryCatalog
        self.algorithm = algorithm
    }

    func fetchSongs(excluding: Set<String>, limit: Int) async throws -> [Song] {
        switch algorithm {
        case .recentlyAdded:
            let fetchLimit = min(excluding.count + limit * 3, 500)
            let page = try await libraryCatalog.fetchLibrarySongs(
                sortedBy: .recentlyAdded, limit: fetchLimit, offset: 0
            )
            let available = page.songs.filter { !excluding.contains($0.id) }
            return Array(available.shuffled().prefix(limit))

        case .random:
            var allSongs: [Song] = []
            var offset = 0
            let pageSize = 500
            while true {
                let page = try await libraryCatalog.fetchLibrarySongs(
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
