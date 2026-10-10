import Foundation

/// The library catalog lanes a listener can browse and search.
public enum LibraryLaneKind: Equatable, CaseIterable {
    case songs
    case artists
    case playlists
}

@Observable
@MainActor
public final class LibraryBrowser {
    deinit {} // Keep nonisolated: Xcode 27 synthesizes an isolated one that can crash on release. See ViewTeardownTests.
    enum Mode: Equatable {
        case browse
        case search
    }

    public enum AutofillState: Equatable {
        case idle
        case loading
        case completed(count: Int)
        case error(String)
    }

    // MARK: - Lanes

    let songsLane: LibraryLane<Song>
    let artistsLane: LibraryLane<Artist>
    let playlistsLane: LibraryLane<Playlist>

    // MARK: - Autofill state

    public private(set) var autofillState: AutofillState = .idle

    // MARK: - Song sort

    public var sortOption: SortOption { preferences.sortOption }

    // MARK: - Active lane

    /// The lane being browsed and searched, or nil while the listener looks
    /// at something other than the catalog, such as their picks. Switching
    /// lanes loads the new lane's first page, or runs the current search on it.
    public var activeLane: LibraryLaneKind? = .songs {
        didSet {
            guard activeLane != oldValue else { return }
            if searchText.isEmpty {
                loadBrowseData(for: activeLane)
            } else {
                handleSearchTextChanged()
            }
        }
    }

    // MARK: - Search text (single source of truth)

    public var searchText = "" {
        didSet {
            guard searchText != oldValue else { return }
            handleSearchTextChanged()
            if searchText.isEmpty {
                loadBrowseData(for: activeLane)
            }
        }
    }

    public var errorMessage: String? {
        songsLane.errorMessage ?? artistsLane.errorMessage ?? playlistsLane.errorMessage
    }

    // MARK: - Computed properties (facade over current lane)

    var currentMode: Mode {
        searchText.isEmpty ? .browse : .search
    }

    var isLoading: Bool {
        currentMode == .browse ? songsLane.isLoading : songsLane.isSearching
    }

    var displayedSongs: [Song] {
        songsLane.currentItems
    }

    // MARK: - Song browse facade

    public var browseSongs: [Song] { songsLane.items }
    public var browseLoading: Bool { songsLane.isLoading }
    public var hasMorePages: Bool { songsLane.hasMorePages }

    // MARK: - Song search facade

    public var searchResults: [Song] { songsLane.searchResults }
    public var searchLoading: Bool { songsLane.isSearching }
    public var hasSearchedOnce: Bool { songsLane.hasSearchedOnce }
    public var hasMoreSearchResults: Bool { songsLane.hasMoreSearchResults }

    // MARK: - Artist browse facade

    public var artists: [Artist] { artistsLane.items }
    public var artistsLoading: Bool { artistsLane.isLoading }
    public var hasMoreArtists: Bool { artistsLane.hasMorePages }

    // MARK: - Artist search facade

    public var artistSearchResults: [Artist] { artistsLane.searchResults }
    public var artistSearchLoading: Bool { artistsLane.isSearching }
    public var hasArtistSearchedOnce: Bool { artistsLane.hasSearchedOnce }
    public var hasMoreArtistSearchResults: Bool { artistsLane.hasMoreSearchResults }

    // MARK: - Playlist browse facade

    public var playlists: [Playlist] { playlistsLane.items }
    public var playlistsLoading: Bool { playlistsLane.isLoading }
    public var hasMorePlaylists: Bool { playlistsLane.hasMorePages }

    // MARK: - Playlist search facade

    public var playlistSearchResults: [Playlist] { playlistsLane.searchResults }
    public var playlistSearchLoading: Bool { playlistsLane.isSearching }
    public var hasPlaylistSearchedOnce: Bool { playlistsLane.hasSearchedOnce }
    public var hasMorePlaylistSearchResults: Bool { playlistsLane.hasMoreSearchResults }

    // MARK: - Dependencies

    @ObservationIgnored private let libraryCatalog: LibraryCatalog
    @ObservationIgnored private let preferences: LibraryPreferences

    // MARK: - Init

    /// - Parameter preferences: Supplies the song sort order and the autofill
    ///   algorithm, and saves a newly chosen sort order.
    public init(libraryCatalog: LibraryCatalog, preferences: LibraryPreferences) {
        self.libraryCatalog = libraryCatalog
        self.preferences = preferences

        // Captures preferences rather than self, which isn't initialized yet.
        self.songsLane = LibraryLane<Song>(
            fetchPage: { [libraryCatalog, preferences] offset, limit in
                let page = try await libraryCatalog.fetchLibrarySongs(
                    sortedBy: preferences.sortOption,
                    limit: limit,
                    offset: offset
                )
                return PageResult(items: page.songs, hasMore: page.hasMore)
            },
            searchPage: { [libraryCatalog] query, offset, limit in
                let page = try await libraryCatalog.searchLibrarySongs(
                    query: query,
                    limit: limit,
                    offset: offset
                )
                return PageResult(items: page.songs, hasMore: page.hasMore)
            }
        )

        // Artists lane
        self.artistsLane = LibraryLane<Artist>(
            fetchPage: { [libraryCatalog] offset, limit in
                let page = try await libraryCatalog.fetchLibraryArtists(limit: limit, offset: offset)
                return PageResult(items: page.artists, hasMore: page.hasMore)
            },
            searchPage: { [libraryCatalog] query, offset, limit in
                let page = try await libraryCatalog.searchLibraryArtists(
                    query: query,
                    limit: limit,
                    offset: offset
                )
                return PageResult(items: page.artists, hasMore: page.hasMore)
            }
        )

        // Playlists lane
        self.playlistsLane = LibraryLane<Playlist>(
            fetchPage: { [libraryCatalog] offset, limit in
                let page = try await libraryCatalog.fetchLibraryPlaylists(limit: limit, offset: offset)
                return PageResult(items: page.playlists, hasMore: page.hasMore)
            },
            searchPage: { [libraryCatalog] query, offset, limit in
                let page = try await libraryCatalog.searchLibraryPlaylists(
                    query: query,
                    limit: limit,
                    offset: offset
                )
                return PageResult(items: page.playlists, hasMore: page.hasMore)
            }
        )
    }

    // MARK: - Sort

    /// Saves `option` as the song sort order and reloads the songs lane in
    /// that order. Choosing the current order does nothing.
    public func chooseSortOption(_ option: SortOption) {
        guard option != preferences.sortOption else { return }
        preferences.sortOption = option
        Task { await songsLane.loadInitial(force: true) }
    }

    // MARK: - Search

    func handleSearchTextChanged() {
        let query = searchText

        if query.isEmpty {
            // Clear all lanes' search state
            songsLane.handleSearchTextChanged("")
            artistsLane.handleSearchTextChanged("")
            playlistsLane.handleSearchTextChanged("")
            return
        }

        switch activeLane {
        case .songs: songsLane.handleSearchTextChanged(query)
        case .artists: artistsLane.handleSearchTextChanged(query)
        case .playlists: playlistsLane.handleSearchTextChanged(query)
        case nil: break
        }
    }

    // MARK: - Song Browse

    public func loadInitialPage() async {
        await songsLane.loadInitial(force: false)
    }

    /// Loads a lane's browse page when it has not been loaded yet.
    func loadBrowseData(for lane: LibraryLaneKind?) {
        Task { @MainActor in
            switch lane {
            case .songs: await songsLane.loadInitial(force: false)
            case .artists: await artistsLane.loadInitial(force: false)
            case .playlists: await playlistsLane.loadInitial(force: false)
            case nil: break
            }
        }
    }

    func loadNextPageIfNeeded(currentSong: Song) async {
        guard songsLane.hasMorePages,
              !songsLane.isLoading,
              currentSong.id == songsLane.items.last?.id else {
            return
        }
        await songsLane.loadMore()
    }

    public func loadMorePages() async {
        await songsLane.loadMore()
    }

    // MARK: - Song Search

    public func loadMoreSearchResults() async {
        await songsLane.loadMoreSearchResults()
    }

    // MARK: - Artist Browse

    func loadInitialArtists() async {
        await artistsLane.loadInitial(force: false)
    }

    public func loadMoreArtists() async {
        await artistsLane.loadMore()
    }

    // MARK: - Artist Search

    public func loadMoreArtistSearchResults() async {
        await artistsLane.loadMoreSearchResults()
    }

    // MARK: - Playlist Browse

    func loadInitialPlaylists() async {
        await playlistsLane.loadInitial(force: false)
    }

    public func loadMorePlaylists() async {
        await playlistsLane.loadMore()
    }

    // MARK: - Playlist Search

    public func loadMorePlaylistSearchResults() async {
        await playlistsLane.loadMoreSearchResults()
    }

    // MARK: - Error

    public func clearError() {
        songsLane.clearError()
        artistsLane.clearError()
        playlistsLane.clearError()
    }

    // MARK: - Autofill

    /// Fills the draft from the library with the saved autofill algorithm.
    public func autofill(into draft: SessionDraftStore) async {
        let source = LibraryAutofillSource(
            libraryCatalog: libraryCatalog,
            algorithm: preferences.autofillAlgorithm
        )
        guard draft.remainingCapacity > 0 else {
            autofillState = .completed(count: 0)
            return
        }

        autofillState = .loading
        do {
            let added = try await draft.autofill(from: source)
            autofillState = .completed(count: added)
        } catch {
            print("🔍 Autofill: ERROR - \(error)")
            autofillState = .error(error.localizedDescription)
        }
    }

    public func resetAutofillState() {
        autofillState = .idle
    }
}