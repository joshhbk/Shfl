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
    @Published private(set) var browseLoading = false
    @Published private(set) var hasMorePages = true
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
    private var searchTask: Task<Void, Never>?

    init(musicService: MusicService) {
        self.musicService = musicService
    }

    // MARK: - Browse Methods

    func loadInitialPage() async {
        browseLoading = true
        currentOffset = 0
        browseSongs = []

        do {
            let page = try await musicService.fetchLibrarySongs(
                sortedBy: sortOption,
                limit: pageSize,
                offset: 0
            )
            browseSongs = page.songs
            hasMorePages = page.hasMore
            currentOffset = page.songs.count
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
}
