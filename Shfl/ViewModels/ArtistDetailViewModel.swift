import Foundation

@Observable
@MainActor
final class ArtistDetailViewModel {
    let lane: LibraryLane<Song>

    // Facade properties for view compatibility
    var songs: [Song] { lane.items }
    var isLoading: Bool { lane.isLoading }
    var hasMorePages: Bool { lane.hasMorePages }
    var errorMessage: String? { lane.errorMessage }

    let artistName: String

    init(artistName: String, musicService: MusicService) {
        self.artistName = artistName
        self.lane = LibraryLane<Song>(
            fetchPage: { offset, limit in
                let page = try await musicService.fetchSongs(
                    byArtist: artistName,
                    limit: limit,
                    offset: offset
                )
                return PageResult(items: page.songs, hasMore: page.hasMore)
            },
            searchPage: { _, _, _ in
                // Artist detail doesn't support search
                return PageResult(items: [], hasMore: false)
            }
        )
    }

    func loadInitialPage() async {
        await lane.loadInitial(force: false)
    }

    func loadMorePages() async {
        await lane.loadMore()
    }
}