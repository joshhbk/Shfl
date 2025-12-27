import Combine
import Foundation

@MainActor
final class LibraryBrowserViewModel: ObservableObject {
    enum Mode: Equatable {
        case browse
        case search
    }

    // Browse state
    @Published private(set) var browseSongs: [Song] = []
    @Published private(set) var browseLoading = true  // Start true to show skeleton
    @Published private(set) var hasMorePages = true
    @Published private(set) var hasLoadedOnce = false
    @Published var sortOption: SortOption = .mostPlayed

    // Search state
    @Published private(set) var searchResults: [Song] = []
    @Published private(set) var searchLoading = false

    // Shared state
    @Published var searchText = ""
    @Published private(set) var errorMessage: String?

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
    private let pageSize = 50
    private var currentOffset = 0
    private var isLoadingMore = false

    // Dependencies
    private let musicService: MusicService
    private var searchCancellable: AnyCancellable?
    private var searchTask: Task<Void, Never>?

    init(musicService: MusicService) {
        self.musicService = musicService
        setupSearchSubscription()
    }

    private func setupSearchSubscription() {
        searchCancellable = $searchText
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] query in
                print("🔎 Debounced search triggered for: '\(query)'")
                guard let self else { return }

                // Clear results immediately when search is cleared
                if query.isEmpty {
                    Task { @MainActor in
                        self.searchResults = []
                    }
                    return
                }

                self.searchTask?.cancel()
                self.searchTask = Task {
                    await self.performSearch(query: query)
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
}
