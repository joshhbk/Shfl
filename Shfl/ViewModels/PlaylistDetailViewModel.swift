import Foundation

@Observable
@MainActor
final class PlaylistDetailViewModel {
    let lane: LibraryLane<Song>

    // Facade properties for view compatibility
    var songs: [Song] { lane.items }
    var isLoading: Bool { lane.isLoading }
    var hasMorePages: Bool { lane.hasMorePages }
    var errorMessage: String? { lane.errorMessage }

    let playlistId: String
    let playlistName: String

    init(playlistId: String, playlistName: String, libraryCatalog: LibraryCatalog) {
        self.playlistId = playlistId
        self.playlistName = playlistName
        self.lane = LibraryLane<Song>(
            fetchPage: { [libraryCatalog, playlistId] offset, limit in
                let page = try await libraryCatalog.fetchSongs(
                    byPlaylistId: playlistId,
                    limit: limit,
                    offset: offset
                )
                return PageResult(items: page.songs, hasMore: page.hasMore)
            },
            searchPage: { _, _, _ in
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