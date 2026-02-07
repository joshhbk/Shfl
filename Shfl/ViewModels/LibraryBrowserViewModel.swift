import Foundation
import SwiftUI

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

    // Autofill state
    private(set) var autofillState: AutofillState = .idle

    // Browse state
    private(set) var browseSongs: [Song] = []
    private(set) var browseLoading = true  // Start true to show skeleton
    private(set) var hasMorePages = true
    private(set) var hasLoadedOnce = false
    var sortOption: SortOption

    // Artist browse state
    private(set) var artists: [Artist] = []
    private(set) var artistsLoading = true
    private(set) var hasMoreArtists = true
    @ObservationIgnored private var hasLoadedArtists = false
    @ObservationIgnored private var artistOffset = 0
    @ObservationIgnored private var isLoadingMoreArtists = false

    // Playlist browse state
    private(set) var playlists: [Playlist] = []
    private(set) var playlistsLoading = true
    private(set) var hasMorePlaylists = true
    @ObservationIgnored private var hasLoadedPlaylists = false
    @ObservationIgnored private var playlistOffset = 0
    @ObservationIgnored private var isLoadingMorePlaylists = false

    // Song search state
    private(set) var searchResults: [Song] = []
    private(set) var searchLoading = false
    private(set) var hasSearchedOnce = false
    private(set) var hasMoreSearchResults = true
    @ObservationIgnored private var searchOffset = 0
    @ObservationIgnored private var isLoadingMoreSearch = false
    @ObservationIgnored private var currentSearchQuery = ""

    // Artist search state
    private(set) var artistSearchResults: [Artist] = []
    private(set) var artistSearchLoading = false
    private(set) var hasArtistSearchedOnce = false
    private(set) var hasMoreArtistSearchResults = true
    @ObservationIgnored private var artistSearchOffset = 0
    @ObservationIgnored private var isLoadingMoreArtistSearch = false

    // Playlist search state
    private(set) var playlistSearchResults: [Playlist] = []
    private(set) var playlistSearchLoading = false
    private(set) var hasPlaylistSearchedOnce = false
    private(set) var hasMorePlaylistSearchResults = true
    @ObservationIgnored private var playlistSearchOffset = 0
    @ObservationIgnored private var isLoadingMorePlaylistSearch = false

    // Browse mode — set by the view so search knows what to search for
    @ObservationIgnored var browseMode: BrowseMode = .songs {
        didSet {
            guard browseMode != oldValue, !searchText.isEmpty else { return }
            handleSearchTextChanged()
        }
    }

    // Shared state - searchText is NOT observed to avoid keystroke lag
    @ObservationIgnored var searchText = "" {
        didSet {
            guard searchText != oldValue else { return }
            handleSearchTextChanged()
        }
    }
    private(set) var errorMessage: String?

    var currentMode: Mode {
        searchText.isEmpty ? .browse : .search
    }

    var isLoading: Bool {
        currentMode == .browse ? browseLoading : searchLoading
    }

    var displayedSongs: [Song] {
        currentMode == .browse ? browseSongs : searchResults
    }

    // Pagination
    @ObservationIgnored private let pageSize = 50
    @ObservationIgnored private var currentOffset = 0
    @ObservationIgnored private var isLoadingMore = false

    // Dependencies
    @ObservationIgnored private let musicService: MusicService
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var debounceTask: Task<Void, Never>?

    init(musicService: MusicService) {
        self.musicService = musicService

        // Read sort option from UserDefaults
        let savedRaw = UserDefaults.standard.string(forKey: "librarySortOption") ?? SortOption.mostPlayed.rawValue
        self.sortOption = SortOption(rawValue: savedRaw) ?? .mostPlayed
    }

    /// Called when sort option changes. Views should call this via onChange(of: appSettings.librarySortOption).
    func handleSortOptionChanged(_ newOption: SortOption) {
        guard newOption != sortOption else { return }

        sortOption = newOption
        currentOffset = 0
        hasMorePages = true

        Task {
            await loadSortedPage()
        }
    }

    /// Loads a fresh page with current sort, animating the transition
    private func loadSortedPage() async {
        do {
            let page = try await musicService.fetchLibrarySongs(
                sortedBy: sortOption,
                limit: pageSize,
                offset: 0
            )

            withAnimation(.smooth) {
                browseSongs = page.songs
            }

            hasMorePages = page.hasMore
            currentOffset = page.songs.count
            hasLoadedOnce = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func handleSearchTextChanged() {
        // Cancel previous debounce
        debounceTask?.cancel()

        let query = searchText

        // Clear results immediately when search is cleared
        if query.isEmpty {
            searchResults = []
            hasSearchedOnce = false
            artistSearchResults = []
            hasArtistSearchedOnce = false
            playlistSearchResults = []
            hasPlaylistSearchedOnce = false
            searchTask?.cancel()
            return
        }

        // Reset search state for new query based on mode
        switch browseMode {
        case .songs: hasSearchedOnce = false
        case .artists: hasArtistSearchedOnce = false
        case .playlists: hasPlaylistSearchedOnce = false
        }

        // Debounce search
        let mode = browseMode
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
            guard !Task.isCancelled else { return }

            print("🔎 Debounced search triggered for: '\(query)' (mode: \(mode))")

            searchTask?.cancel()
            searchTask = Task {
                switch mode {
                case .songs:
                    await performSearch(query: query)
                case .artists:
                    await performArtistSearch(query: query)
                case .playlists:
                    await performPlaylistSearch(query: query)
                }
            }
        }
    }

    // MARK: - Browse Methods

    func loadInitialPage() async {
        // Skip if already loaded (e.g., returning to view)
        guard !hasLoadedOnce else {
            browseLoading = false
            return
        }

        browseLoading = true
        currentOffset = 0

        do {
            let page = try await musicService.fetchLibrarySongs(
                sortedBy: sortOption,
                limit: pageSize,
                offset: 0
            )
            browseSongs = page.songs
            hasMorePages = page.hasMore
            currentOffset = page.songs.count
            hasLoadedOnce = true
        } catch {
            errorMessage = error.localizedDescription
        }

        browseLoading = false
    }

    func loadNextPageIfNeeded(currentSong: Song) async {
        guard hasMorePages,
              !isLoadingMore,
              currentSong.id == browseSongs.last?.id else {
            return
        }

        await loadMorePages()
    }

    func loadMorePages() async {
        guard hasMorePages, !isLoadingMore else { return }

        isLoadingMore = true

        do {
            let page = try await musicService.fetchLibrarySongs(
                sortedBy: sortOption,
                limit: pageSize,
                offset: currentOffset
            )
            browseSongs.append(contentsOf: page.songs)
            hasMorePages = page.hasMore
            currentOffset += page.songs.count
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoadingMore = false
    }

    // MARK: - Search Methods

    func performSearch(query: String) async {
        print("🔎 performSearch called with: '\(query)'")
        guard !query.isEmpty else {
            searchResults = []
            return
        }

        searchLoading = true
        searchOffset = 0
        currentSearchQuery = query

        do {
            let page = try await musicService.searchLibrarySongs(
                query: query,
                limit: pageSize,
                offset: 0
            )
            searchResults = page.songs
            hasMoreSearchResults = page.hasMore
            searchOffset = page.songs.count
            print("🔎 Got \(searchResults.count) search results, hasMore: \(hasMoreSearchResults)")
        } catch {
            print("🔎 Search error: \(error)")
            errorMessage = error.localizedDescription
        }

        searchLoading = false
        hasSearchedOnce = true
    }

    func loadMoreSearchResults() async {
        guard hasMoreSearchResults, !isLoadingMoreSearch, !currentSearchQuery.isEmpty else { return }

        isLoadingMoreSearch = true

        do {
            let page = try await musicService.searchLibrarySongs(
                query: currentSearchQuery,
                limit: pageSize,
                offset: searchOffset
            )
            searchResults.append(contentsOf: page.songs)
            hasMoreSearchResults = page.hasMore
            searchOffset += page.songs.count
            print("🔎 Loaded \(page.songs.count) more search results, total: \(searchResults.count)")
        } catch {
            print("🔎 Load more search error: \(error)")
            errorMessage = error.localizedDescription
        }

        isLoadingMoreSearch = false
    }

    // MARK: - Artist Search Methods

    func performArtistSearch(query: String) async {
        guard !query.isEmpty else {
            artistSearchResults = []
            return
        }

        artistSearchLoading = true
        artistSearchOffset = 0
        currentSearchQuery = query

        do {
            let page = try await musicService.searchLibraryArtists(
                query: query,
                limit: pageSize,
                offset: 0
            )
            artistSearchResults = page.artists
            hasMoreArtistSearchResults = page.hasMore
            artistSearchOffset = page.artists.count
        } catch {
            errorMessage = error.localizedDescription
        }

        artistSearchLoading = false
        hasArtistSearchedOnce = true
    }

    func loadMoreArtistSearchResults() async {
        guard hasMoreArtistSearchResults, !isLoadingMoreArtistSearch, !currentSearchQuery.isEmpty else { return }

        isLoadingMoreArtistSearch = true

        do {
            let page = try await musicService.searchLibraryArtists(
                query: currentSearchQuery,
                limit: pageSize,
                offset: artistSearchOffset
            )
            artistSearchResults.append(contentsOf: page.artists)
            hasMoreArtistSearchResults = page.hasMore
            artistSearchOffset += page.artists.count
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoadingMoreArtistSearch = false
    }

    // MARK: - Playlist Search Methods

    func performPlaylistSearch(query: String) async {
        guard !query.isEmpty else {
            playlistSearchResults = []
            return
        }

        playlistSearchLoading = true
        playlistSearchOffset = 0
        currentSearchQuery = query

        do {
            let page = try await musicService.searchLibraryPlaylists(
                query: query,
                limit: pageSize,
                offset: 0
            )
            playlistSearchResults = page.playlists
            hasMorePlaylistSearchResults = page.hasMore
            playlistSearchOffset = page.playlists.count
        } catch {
            errorMessage = error.localizedDescription
        }

        playlistSearchLoading = false
        hasPlaylistSearchedOnce = true
    }

    func loadMorePlaylistSearchResults() async {
        guard hasMorePlaylistSearchResults, !isLoadingMorePlaylistSearch, !currentSearchQuery.isEmpty else { return }

        isLoadingMorePlaylistSearch = true

        do {
            let page = try await musicService.searchLibraryPlaylists(
                query: currentSearchQuery,
                limit: pageSize,
                offset: playlistSearchOffset
            )
            playlistSearchResults.append(contentsOf: page.playlists)
            hasMorePlaylistSearchResults = page.hasMore
            playlistSearchOffset += page.playlists.count
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoadingMorePlaylistSearch = false
    }

    func clearError() {
        errorMessage = nil
    }

    // MARK: - Artist Browse Methods

    func loadInitialArtists() async {
        guard !hasLoadedArtists else {
            artistsLoading = false
            return
        }

        artistsLoading = true
        artistOffset = 0

        do {
            let page = try await musicService.fetchLibraryArtists(limit: pageSize, offset: 0)
            artists = page.artists
            hasMoreArtists = page.hasMore
            artistOffset = page.artists.count
            hasLoadedArtists = true
        } catch {
            errorMessage = error.localizedDescription
        }

        artistsLoading = false
    }

    func loadMoreArtists() async {
        guard hasMoreArtists, !isLoadingMoreArtists else { return }

        isLoadingMoreArtists = true

        do {
            let page = try await musicService.fetchLibraryArtists(limit: pageSize, offset: artistOffset)
            artists.append(contentsOf: page.artists)
            hasMoreArtists = page.hasMore
            artistOffset += page.artists.count
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoadingMoreArtists = false
    }

    // MARK: - Playlist Browse Methods

    func loadInitialPlaylists() async {
        guard !hasLoadedPlaylists else {
            playlistsLoading = false
            return
        }

        playlistsLoading = true
        playlistOffset = 0

        do {
            let page = try await musicService.fetchLibraryPlaylists(limit: pageSize, offset: 0)
            playlists = page.playlists
            hasMorePlaylists = page.hasMore
            playlistOffset = page.playlists.count
            hasLoadedPlaylists = true
        } catch {
            errorMessage = error.localizedDescription
        }

        playlistsLoading = false
    }

    func loadMorePlaylists() async {
        guard hasMorePlaylists, !isLoadingMorePlaylists else { return }

        isLoadingMorePlaylists = true

        do {
            let page = try await musicService.fetchLibraryPlaylists(limit: pageSize, offset: playlistOffset)
            playlists.append(contentsOf: page.playlists)
            hasMorePlaylists = page.hasMore
            playlistOffset += page.playlists.count
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoadingMorePlaylists = false
    }

    // MARK: - Autofill Methods

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
