import Foundation

@Observable
@MainActor
public final class ArtistDetailViewModel {
    deinit {} // Keep nonisolated: Xcode 27 synthesizes an isolated one that can crash on release. See ViewTeardownTests.
    let lane: LibraryLane<Song>

    // Facade properties for view compatibility
    public var songs: [Song] { lane.items }
    public var isLoading: Bool { lane.isLoading }
    public var hasMorePages: Bool { lane.hasMorePages }
    var errorMessage: String? { lane.errorMessage }

    public let artistName: String

    public init(artistName: String, libraryCatalog: LibraryCatalog) {
        self.artistName = artistName
        self.lane = LibraryLane<Song>(
            fetchPage: { offset, limit in
                let page = try await libraryCatalog.fetchSongs(
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

    public func loadInitialPage() async {
        await lane.loadInitial(force: false)
    }

    public func loadMorePages() async {
        await lane.loadMore()
    }
}