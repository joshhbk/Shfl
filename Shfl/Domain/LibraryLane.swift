import Foundation

// MARK: - PageResult

struct PageResult<Item> {
    let items: [Item]
    let hasMore: Bool
}

// MARK: - LibraryLane

/// A generic paginated library browsing lane with search.
///
/// Owns all pagination state, loading, search debounce, and error handling.
/// Small adapters provide the fetch and search functions for each entity type
/// (songs, artists, playlists, artist detail, playlist detail).
@Observable
@MainActor
final class LibraryLane<Item: Sendable> {
    // MARK: - Adapter closures

    @ObservationIgnored private let pageSize: Int
    @ObservationIgnored private let fetchPage: (_ offset: Int, _ limit: Int) async throws -> PageResult<Item>
    @ObservationIgnored private let searchPage: (_ query: String, _ offset: Int, _ limit: Int) async throws -> PageResult<Item>

    // MARK: - Published browse state

    private(set) var items: [Item] = []
    private(set) var isLoading = false
    private(set) var hasMorePages = true
    private(set) var errorMessage: String?

    // MARK: - Published search state

    private(set) var searchResults: [Item] = []
    private(set) var isSearching = false
    private(set) var hasSearchedOnce = false
    private(set) var hasMoreSearchResults = true

    // MARK: - Non-observed internal state

    @ObservationIgnored private var offset = 0
    @ObservationIgnored private var isLoadingMore = false
    @ObservationIgnored private var searchOffset = 0
    @ObservationIgnored private var isLoadingMoreSearch = false
    @ObservationIgnored private var currentQuery = ""
    @ObservationIgnored private var hasLoadedOnce = false

    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var debounceTask: Task<Void, Never>?

    // MARK: - Convenience

    /// The items to display — browse items when no active search, search results otherwise.
    var currentItems: [Item] {
        searchText.isEmpty ? items : searchResults
    }

    /// Whether the lane is currently in search mode.
    var isActiveSearch: Bool {
        !searchText.isEmpty
    }

    /// The current search query. Empty when browsing.
    var searchText: String {
        currentQuery
    }

    // MARK: - Init

    init(
        pageSize: Int = 50,
        fetchPage: @escaping (_ offset: Int, _ limit: Int) async throws -> PageResult<Item>,
        searchPage: @escaping (_ query: String, _ offset: Int, _ limit: Int) async throws -> PageResult<Item>
    ) {
        self.pageSize = pageSize
        self.fetchPage = fetchPage
        self.searchPage = searchPage
    }

    // MARK: - Browse

    /// Loads the initial page. Skips if already loaded unless `force` is true.
    func loadInitial(force: Bool = false) async {
        guard force || !hasLoadedOnce else {
            isLoading = false
            return
        }

        isLoading = true
        offset = 0

        do {
            let result = try await fetchPage(0, pageSize)
            items = result.items
            hasMorePages = result.hasMore
            offset = result.items.count
            hasLoadedOnce = true
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// Loads the next page when the last item is displayed.
    func loadMore() async {
        guard hasMorePages, !isLoadingMore else { return }

        isLoadingMore = true

        do {
            let result = try await fetchPage(offset, pageSize)
            items.append(contentsOf: result.items)
            hasMorePages = result.hasMore
            offset += result.items.count
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoadingMore = false
    }

    // MARK: - Search

    /// Called when the user changes the search text. Handles debounce internally.
    func handleSearchTextChanged(_ query: String) {
        debounceTask?.cancel()

        if query.isEmpty {
            searchResults = []
            hasSearchedOnce = false
            currentQuery = ""
            searchTask?.cancel()
            return
        }

        hasSearchedOnce = false
        currentQuery = query

        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled, query == self.currentQuery else { return }

            searchTask?.cancel()
            searchTask = Task {
                await performSearch(query: query)
            }
        }
    }

    private func performSearch(query: String) async {
        guard !query.isEmpty else {
            searchResults = []
            return
        }

        isSearching = true
        searchOffset = 0

        do {
            let result = try await searchPage(query, 0, pageSize)
            searchResults = result.items
            hasMoreSearchResults = result.hasMore
            searchOffset = result.items.count
        } catch {
            errorMessage = error.localizedDescription
        }

        isSearching = false
        hasSearchedOnce = true
    }

    /// Loads more search results for paginated search.
    func loadMoreSearchResults() async {
        guard hasMoreSearchResults, !isLoadingMoreSearch, !currentQuery.isEmpty else { return }

        isLoadingMoreSearch = true

        do {
            let result = try await searchPage(currentQuery, searchOffset, pageSize)
            searchResults.append(contentsOf: result.items)
            hasMoreSearchResults = result.hasMore
            searchOffset += result.items.count
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoadingMoreSearch = false
    }

    // MARK: - Reset

    /// Clears the error message without resetting all state.
    func clearError() {
        errorMessage = nil
    }

    /// Clears all state. Used when the lane needs a full reload.
    func reset() {
        items = []
        isLoading = false
        hasMorePages = true
        errorMessage = nil
        searchResults = []
        isSearching = false
        hasSearchedOnce = false
        hasMoreSearchResults = true

        offset = 0
        isLoadingMore = false
        searchOffset = 0
        isLoadingMoreSearch = false
        currentQuery = ""
        hasLoadedOnce = false

        searchTask?.cancel()
        debounceTask?.cancel()
        searchTask = nil
        debounceTask = nil
    }
}