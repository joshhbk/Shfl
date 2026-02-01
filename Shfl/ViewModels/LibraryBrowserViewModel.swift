import Foundation

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

    // Search state
    private(set) var searchResults: [Song] = []
    private(set) var searchLoading = false

    // Shared state
    var searchText = "" {
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
        hasLoadedOnce = false
        browseSongs = []
        currentOffset = 0
        hasMorePages = true

        Task {
            await loadInitialPage()
        }
    }

    private func handleSearchTextChanged() {
        // Cancel previous debounce
        debounceTask?.cancel()

        let query = searchText

        // Clear results immediately when search is cleared
        if query.isEmpty {
            searchResults = []
            searchTask?.cancel()
            return
        }

        // Debounce search
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
            guard !Task.isCancelled else { return }

            print("🔎 Debounced search triggered for: '\(query)'")

            searchTask?.cancel()
            searchTask = Task {
                await performSearch(query: query)
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

        do {
            searchResults = try await musicService.searchLibrarySongs(query: query)
            print("🔎 Got \(searchResults.count) search results")
        } catch {
            print("🔎 Search error: \(error)")
            errorMessage = error.localizedDescription
        }

        searchLoading = false
    }

    func clearError() {
        errorMessage = nil
    }

    // MARK: - Autofill Methods

    func autofill(into player: ShufflePlayer, using source: AutofillSource) async {
        let limit = player.remainingCapacity
        guard limit > 0 else {
            autofillState = .completed(count: 0)
            return
        }

        autofillState = .loading

        do {
            let excludedIds = Set(player.allSongs.map { $0.id })
            let songs = try await source.fetchSongs(excluding: excludedIds, limit: limit)

            // Use batch method for single queue rebuild
            try await player.addSongsWithQueueRebuild(songs)

            autofillState = .completed(count: songs.count)
        } catch {
            autofillState = .error(error.localizedDescription)
        }
    }

    func resetAutofillState() {
        autofillState = .idle
    }
}
