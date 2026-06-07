import Foundation
import SwiftUI

/// Reference box so sortOption can be captured by closures during init without capturing self.
private final class SortOptionRef {
    var value: SortOption
    init(_ value: SortOption) { self.value = value }
}

@Observable
@MainActor
final class LibraryBrowserViewModel {
    enum Mode: Equatable {
        case browse
        case search
    }

    enum AutofillState: Equatable {
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

    private(set) var autofillState: AutofillState = .idle

    // MARK: - Song sort (wrapped in ref box for closure capture during init)

    @ObservationIgnored private let _sortOption: SortOptionRef

    var sortOption: SortOption {
        get { _sortOption.value }
        set {
            _sortOption.value = newValue
            Task { await songsLane.loadInitial(force: true) }
        }
    }

    // MARK: - Browse mode

    @ObservationIgnored var browseMode: BrowseMode = .songs {
        didSet {
            guard browseMode != oldValue, !searchText.isEmpty else { return }
            handleSearchTextChanged()
        }
    }

    // MARK: - Search text (single source of truth)

    @ObservationIgnored var searchText = "" {
        didSet {
            guard searchText != oldValue else { return }
            handleSearchTextChanged()
        }
    }

    var errorMessage: String? {
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

    var browseSongs: [Song] { songsLane.items }
    var browseLoading: Bool { songsLane.isLoading }
    var hasMorePages: Bool { songsLane.hasMorePages }

    // MARK: - Song search facade

    var searchResults: [Song] { songsLane.searchResults }
    var searchLoading: Bool { songsLane.isSearching }
    var hasSearchedOnce: Bool { songsLane.hasSearchedOnce }
    var hasMoreSearchResults: Bool { songsLane.hasMoreSearchResults }

    // MARK: - Artist browse facade

    var artists: [Artist] { artistsLane.items }
    var artistsLoading: Bool { artistsLane.isLoading }
    var hasMoreArtists: Bool { artistsLane.hasMorePages }

    // MARK: - Artist search facade

    var artistSearchResults: [Artist] { artistsLane.searchResults }
    var artistSearchLoading: Bool { artistsLane.isSearching }
    var hasArtistSearchedOnce: Bool { artistsLane.hasSearchedOnce }
    var hasMoreArtistSearchResults: Bool { artistsLane.hasMoreSearchResults }

    // MARK: - Playlist browse facade

    var playlists: [Playlist] { playlistsLane.items }
    var playlistsLoading: Bool { playlistsLane.isLoading }
    var hasMorePlaylists: Bool { playlistsLane.hasMorePages }

    // MARK: - Playlist search facade

    var playlistSearchResults: [Playlist] { playlistsLane.searchResults }
    var playlistSearchLoading: Bool { playlistsLane.isSearching }
    var hasPlaylistSearchedOnce: Bool { playlistsLane.hasSearchedOnce }
    var hasMorePlaylistSearchResults: Bool { playlistsLane.hasMoreSearchResults }

    // MARK: - Dependencies

    @ObservationIgnored private let musicService: MusicService

    // MARK: - Init

    init(musicService: MusicService, initialSortOption: SortOption = .mostPlayed) {
        self.musicService = musicService
        let sortRef = SortOptionRef(initialSortOption)
        self._sortOption = sortRef

        // Songs lane — captures sortRef instead of self to avoid "used before initialized"
        self.songsLane = LibraryLane<Song>(
            fetchPage: { [musicService, sortRef] offset, limit in
                let page = try await musicService.fetchLibrarySongs(
                    sortedBy: sortRef.value,
                    limit: limit,
                    offset: offset
                )
                return PageResult(items: page.songs, hasMore: page.hasMore)
            },
            searchPage: { [musicService] query, offset, limit in
                let page = try await musicService.searchLibrarySongs(
                    query: query,
                    limit: limit,
                    offset: offset
                )
                return PageResult(items: page.songs, hasMore: page.hasMore)
            }
        )

        // Artists lane
        self.artistsLane = LibraryLane<Artist>(
            fetchPage: { [musicService] offset, limit in
                let page = try await musicService.fetchLibraryArtists(limit: limit, offset: offset)
                return PageResult(items: page.artists, hasMore: page.hasMore)
            },
            searchPage: { [musicService] query, offset, limit in
                let page = try await musicService.searchLibraryArtists(
                    query: query,
                    limit: limit,
                    offset: offset
                )
                return PageResult(items: page.artists, hasMore: page.hasMore)
            }
        )

        // Playlists lane
        self.playlistsLane = LibraryLane<Playlist>(
            fetchPage: { [musicService] offset, limit in
                let page = try await musicService.fetchLibraryPlaylists(limit: limit, offset: offset)
                return PageResult(items: page.playlists, hasMore: page.hasMore)
            },
            searchPage: { [musicService] query, offset, limit in
                let page = try await musicService.searchLibraryPlaylists(
                    query: query,
                    limit: limit,
                    offset: offset
                )
                return PageResult(items: page.playlists, hasMore: page.hasMore)
            }
        )
    }

    // MARK: - Sort

    /// Called when sort option changes. Views should call this via onChange(of: appSettings.librarySortOption).
    func handleSortOptionChanged(_ newOption: SortOption) {
        sortOption = newOption
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

        // Forward to the current lane based on browse mode
        switch browseMode {
        case .songs: songsLane.handleSearchTextChanged(query)
        case .artists: artistsLane.handleSearchTextChanged(query)
        case .playlists: playlistsLane.handleSearchTextChanged(query)
        }
    }

    // MARK: - Song Browse

    func loadInitialPage() async {
        await songsLane.loadInitial(force: false)
    }

    func loadNextPageIfNeeded(currentSong: Song) async {
        guard songsLane.hasMorePages,
              !songsLane.isLoading,
              currentSong.id == songsLane.items.last?.id else {
            return
        }
        await songsLane.loadMore()
    }

    func loadMorePages() async {
        await songsLane.loadMore()
    }

    // MARK: - Song Search

    func loadMoreSearchResults() async {
        await songsLane.loadMoreSearchResults()
    }

    // MARK: - Artist Browse

    func loadInitialArtists() async {
        await artistsLane.loadInitial(force: false)
    }

    func loadMoreArtists() async {
        await artistsLane.loadMore()
    }

    // MARK: - Artist Search

    func loadMoreArtistSearchResults() async {
        await artistsLane.loadMoreSearchResults()
    }

    // MARK: - Playlist Browse

    func loadInitialPlaylists() async {
        await playlistsLane.loadInitial(force: false)
    }

    func loadMorePlaylists() async {
        await playlistsLane.loadMore()
    }

    // MARK: - Playlist Search

    func loadMorePlaylistSearchResults() async {
        await playlistsLane.loadMoreSearchResults()
    }

    // MARK: - Error

    func clearError() {
        songsLane.clearError()
        artistsLane.clearError()
        playlistsLane.clearError()
    }

    // MARK: - Autofill

    func autofill(
        into player: ShufflePlayer,
        using source: AutofillSource,
        addSongs: ([Song]) async throws -> Void
    ) async {
        let limit = player.remainingCapacity
        print("🔍 Autofill: Starting with limit \(limit)")
        guard limit > 0 else {
            autofillState = .completed(count: 0)
            return
        }

        autofillState = .loading
        print("🔍 Autofill: State set to loading")

        do {
            let excludedIds = Set(player.allSongs.map { $0.id })
            print("🔍 Autofill: Calling fetchSongs with \(excludedIds.count) excluded...")
            let songs = try await source.fetchSongs(excluding: excludedIds, limit: limit)
            print("🔍 Autofill: Fetched \(songs.count) songs")

            print("🔍 Autofill: Applying songs to queue...")
            try await addSongs(songs)
            print("🔍 Autofill: song application complete")

            autofillState = .completed(count: songs.count)
            print("🔍 Autofill: Complete!")
        } catch {
            print("🔍 Autofill: ERROR - \(error)")
            autofillState = .error(error.localizedDescription)
        }
    }

    func resetAutofillState() {
        autofillState = .idle
    }
}