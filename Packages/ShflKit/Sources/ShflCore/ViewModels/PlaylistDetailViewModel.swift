import Foundation

@Observable
@MainActor
public final class PlaylistDetailViewModel {
    deinit {} // Keep nonisolated: Xcode 27 synthesizes an isolated one that can crash on release. See ViewTeardownTests.
    let lane: LibraryLane<Song>

    // Facade properties for view compatibility
    public var songs: [Song] { lane.items }
    public var isLoading: Bool { lane.isLoading }
    public var hasMorePages: Bool { lane.hasMorePages }
    var errorMessage: String? { lane.errorMessage }

    let playlistId: String
    public let playlistName: String

    public init(playlistId: String, playlistName: String, libraryCatalog: LibraryCatalog) {
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

    public func loadInitialPage() async {
        await lane.loadInitial(force: false)
    }

    public func loadMorePages() async {
        await lane.loadMore()
    }
}