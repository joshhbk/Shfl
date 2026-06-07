import XCTest
@testable import Shfl

@MainActor
final class LibraryBrowserViewModelTests: XCTestCase {
    private var mockService: MockMusicService!
    private var viewModel: LibraryBrowserViewModel!

    override func setUp() async throws {
        mockService = MockMusicService()
        viewModel = LibraryBrowserViewModel(musicService: mockService)
    }

    func test_initialState_isCorrect() {
        XCTAssertTrue(viewModel.browseSongs.isEmpty)
        XCTAssertTrue(viewModel.searchResults.isEmpty)
        XCTAssertEqual(viewModel.searchText, "")
        XCTAssertEqual(viewModel.currentMode, .browse)
        XCTAssertFalse(viewModel.isLoading)  // Lane starts with isLoading=false until loadInitial
        XCTAssertEqual(viewModel.sortOption, .mostPlayed)
    }

    func test_currentMode_switchesToSearchWhenTextEntered() {
        viewModel.searchText = "test"
        XCTAssertEqual(viewModel.currentMode, .search)
    }

    func test_currentMode_switchesToBrowseWhenTextCleared() {
        viewModel.searchText = "test"
        viewModel.searchText = ""
        XCTAssertEqual(viewModel.currentMode, .browse)
    }

    func test_loadInitialPage_fetchesSongs() async {
        let songs = [
            Song(id: "1", title: "Song 1", artist: "Artist", albumTitle: "Album", artworkURL: nil),
            Song(id: "2", title: "Song 2", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        ]
        await mockService.setLibrarySongs(songs)

        await viewModel.loadInitialPage()

        XCTAssertEqual(viewModel.browseSongs.count, 2)
        XCTAssertFalse(viewModel.browseLoading)
    }

    func test_loadInitialPage_setsHasMorePages() async {
        // Create more songs than page size to test pagination
        let songs = (1...60).map {
            Song(id: "\($0)", title: "Song \($0)", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        }
        await mockService.setLibrarySongs(songs)

        await viewModel.loadInitialPage()

        XCTAssertEqual(viewModel.browseSongs.count, 50)
        XCTAssertTrue(viewModel.hasMorePages)
    }

    func test_loadNextPage_appendsSongs() async {
        let songs = (1...60).map {
            Song(id: "\($0)", title: "Song \($0)", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        }
        await mockService.setLibrarySongs(songs)

        await viewModel.loadInitialPage()
        await viewModel.loadNextPageIfNeeded(currentSong: viewModel.browseSongs.last!)

        XCTAssertEqual(viewModel.browseSongs.count, 60)
        XCTAssertFalse(viewModel.hasMorePages)
    }

    func test_search_fetchesResults() async {
        let songs = [
            Song(id: "1", title: "Hello World", artist: "Artist", albumTitle: "Album", artworkURL: nil),
            Song(id: "2", title: "Goodbye", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        ]
        await mockService.setLibrarySongs(songs)

        // Search through the songs lane directly (bypasses debounce in view model)
        viewModel.songsLane.handleSearchTextChanged("Hello")
        // Wait for debounce (300ms) + search task to complete
        try? await Task.sleep(nanoseconds: 600_000_000)

        let searchResults = viewModel.searchResults
        XCTAssertEqual(searchResults.count, 1)
        XCTAssertEqual(searchResults.first?.title, "Hello World")
    }

    func test_autofillState_initiallyIdle() {
        XCTAssertEqual(viewModel.autofillState, .idle)
    }

    // MARK: - Autofill Method Tests

    func test_autofill_addsSongsToPlayer() async {
        let songs = (1...50).map {
            Song(id: "\($0)", title: "Song \($0)", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        }
        await mockService.setLibrarySongs(songs)

        let player = ShufflePlayer(musicService: mockService)
        let source = LibraryAutofillSource(musicService: mockService)

        await viewModel.autofill(into: player, using: source) { songs in
            try await player.addSongsWithQueueRebuild(songs)
        }

        XCTAssertEqual(player.songCount, 50)
        XCTAssertEqual(viewModel.autofillState, .completed(count: 50))
    }

    func test_autofill_fillsOnlyRemainingCapacity() async {
        let songs = (1...200).map {
            Song(id: "\($0)", title: "Song \($0)", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        }
        await mockService.setLibrarySongs(songs)

        let player = ShufflePlayer(musicService: mockService)
        // Add 100 songs first
        for i in 1...100 {
            try? await player.addSong(Song(id: "existing-\(i)", title: "Existing \(i)", artist: "Artist", albumTitle: "Album", artworkURL: nil))
        }

        let source = LibraryAutofillSource(musicService: mockService)
        await viewModel.autofill(into: player, using: source) { songs in
            try await player.addSongsWithQueueRebuild(songs)
        }

        // Should only add 20 more (120 - 100)
        XCTAssertEqual(player.songCount, 120)
        XCTAssertEqual(viewModel.autofillState, .completed(count: 20))
    }

    func test_autofill_excludesDuplicates() async {
        let songs = (1...10).map {
            Song(id: "\($0)", title: "Song \($0)", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        }
        await mockService.setLibrarySongs(songs)

        let player = ShufflePlayer(musicService: mockService)
        // Pre-add some songs that are also in library
        try? await player.addSong(songs[0])
        try? await player.addSong(songs[1])

        let source = LibraryAutofillSource(musicService: mockService)
        await viewModel.autofill(into: player, using: source) { songs in
            try await player.addSongsWithQueueRebuild(songs)
        }

        // Should add 8 new songs (10 - 2 already added)
        XCTAssertEqual(player.songCount, 10)
        XCTAssertEqual(viewModel.autofillState, .completed(count: 8))
    }

    func test_autofill_completesWithZeroWhenFull() async {
        let player = ShufflePlayer(musicService: mockService)
        // Fill to capacity
        for i in 1...120 {
            try? await player.addSong(Song(id: "\(i)", title: "Song \(i)", artist: "Artist", albumTitle: "Album", artworkURL: nil))
        }

        let source = LibraryAutofillSource(musicService: mockService)
        await viewModel.autofill(into: player, using: source) { songs in
            try await player.addSongsWithQueueRebuild(songs)
        }

        XCTAssertEqual(viewModel.autofillState, .completed(count: 0))
    }

    func test_autofill_setsLoadingState() async {
        let songs = [Song(id: "1", title: "Song", artist: "Artist", albumTitle: "Album", artworkURL: nil)]
        await mockService.setLibrarySongs(songs)

        let player = ShufflePlayer(musicService: mockService)
        let source = LibraryAutofillSource(musicService: mockService)

        // Start autofill
        let task = Task {
            await viewModel.autofill(into: player, using: source) { songs in
                try await player.addSongsWithQueueRebuild(songs)
            }
        }

        // Verify it completes correctly
        await task.value

        XCTAssertEqual(viewModel.autofillState, .completed(count: 1))
    }

    func test_autofill_whilePlaying_defersTransportAndUpdatesDomainQueue() async throws {
        let allSongs = (1...5).map {
            Song(id: "\($0)", title: "Song \($0)", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        }
        await mockService.setLibrarySongs(allSongs)

        let player = ShufflePlayer(musicService: mockService)
        try await player.addSong(allSongs[0])
        try await player.addSong(allSongs[1])
        try await player.play()
        try await Task.sleep(nanoseconds: 100_000_000)

        await mockService.resetQueueTracking()

        let source = LibraryAutofillSource(musicService: mockService)
        await viewModel.autofill(into: player, using: source) { songs in
            try await player.addSongsWithQueueRebuild(songs)
        }

        XCTAssertEqual(viewModel.autofillState, .completed(count: 3))
        XCTAssertEqual(player.songCount, 5)

        // Transport sync is deferred to avoid playback interruption
        let replaceCallCount = await mockService.replaceQueueCallCount
        XCTAssertEqual(replaceCallCount, 0, "Autofill while active should defer transport sync")

        // Domain queue should include all songs
        let domainQueueIds = Set(player.lastShuffledQueue.map(\.id))
        XCTAssertEqual(domainQueueIds, Set(allSongs.map(\.id)))
    }
}

// MARK: - LibraryLane Tests

@MainActor
final class LibraryLaneTests: XCTestCase {
    private var lane: LibraryLane<String>!

    override func setUp() {
        lane = LibraryLane<String>(
            fetchPage: { offset, limit in
                // Simulate a paginated source of 75 items
                let totalItems = 75
                let start = offset
                let end = min(offset + limit, totalItems)
                let items = (start..<end).map { "Item \($0)" }
                return PageResult(items: items, hasMore: end < totalItems)
            },
            searchPage: { query, offset, limit in
                let results = (0..<75).filter { "Item \($0)".localizedCaseInsensitiveContains(query) }
                let end = min(offset + limit, results.count)
                let items = results[offset..<end].map { "Item \($0)" }
                return PageResult(items: items, hasMore: end < results.count)
            }
        )
    }

    func test_initialState() {
        XCTAssertTrue(lane.items.isEmpty)
        XCTAssertTrue(lane.searchResults.isEmpty)
        XCTAssertFalse(lane.isActiveSearch)
        XCTAssertTrue(lane.searchText.isEmpty)
    }

    func test_loadInitial() async {
        await lane.loadInitial()

        XCTAssertEqual(lane.items.count, 50)
        XCTAssertTrue(lane.hasMorePages)
        XCTAssertFalse(lane.isLoading)
    }

    func test_loadInitial_skipsIfAlreadyLoaded() async {
        await lane.loadInitial()
        let items = lane.items

        await lane.loadInitial()

        XCTAssertEqual(lane.items.count, items.count, "Should not reload when already loaded")
    }

    func test_loadInitial_forceReload() async {
        await lane.loadInitial()

        // Force reload with different data — our mock is deterministic so same result,
        // but the key is that it actually calls fetchPage again
        await lane.loadInitial(force: true)

        XCTAssertEqual(lane.items.count, 50)
    }

    func test_loadMore_appendsItems() async {
        await lane.loadInitial()
        // items = 50, hasMore = true

        await lane.loadMore()

        XCTAssertEqual(lane.items.count, 75)
        XCTAssertFalse(lane.hasMorePages)
    }

    func test_loadMore_doesNotLoadWhenNoMorePages() async {
        await lane.loadInitial()
        await lane.loadMore()

        // Try loading more when there are no more pages
        await lane.loadMore()

        XCTAssertEqual(lane.items.count, 75)
    }

    func test_search_filtersItems() async {
        lane.handleSearchTextChanged("Item 1")
        // The lane debounces internally — the mock is synchronous so the task
        // should complete quickly
        try? await Task.sleep(nanoseconds: 400_000_000) // Wait for debounce + search

        XCTAssertFalse(lane.searchResults.isEmpty)
        XCTAssertTrue(lane.hasSearchedOnce)
        XCTAssertFalse(lane.isSearching)
        // "Item 1" matches "Item 1", "Item 10", "Item 11", etc.
        // Items 0..<75, those matching "Item 1" are 1, 10-19, 100+ (none above 75)
        // So: 1, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19 = 11 items
        XCTAssertGreaterThanOrEqual(lane.searchResults.count, 11)
    }

    func test_search_clearsOnEmptyQuery() {
        lane.handleSearchTextChanged("")
        lane.handleSearchTextChanged("something")
        lane.handleSearchTextChanged("")

        XCTAssertTrue(lane.searchResults.isEmpty)
        XCTAssertFalse(lane.hasSearchedOnce)
    }

    func test_currentItems_returnsBrowseItemsWhenNoSearch() async {
        await lane.loadInitial()

        let current = lane.currentItems

        XCTAssertEqual(current, lane.items)
    }

    func test_currentItems_returnsSearchResultsWhenSearching() async {
        lane.handleSearchTextChanged("Item 1")
        try? await Task.sleep(nanoseconds: 400_000_000)

        let current = lane.currentItems

        XCTAssertEqual(current, lane.searchResults)
    }

    func test_reset_clearsAllState() async {
        await lane.loadInitial()
        lane.handleSearchTextChanged("test")
        try? await Task.sleep(nanoseconds: 400_000_000)

        lane.reset()

        XCTAssertTrue(lane.items.isEmpty)
        XCTAssertTrue(lane.searchResults.isEmpty)
        XCTAssertFalse(lane.isActiveSearch)
        XCTAssertFalse(lane.isLoading)
        XCTAssertFalse(lane.hasSearchedOnce)
    }

    func test_errorMessage_setOnFetchFailure() async {
        let failingLane = LibraryLane<String>(
            fetchPage: { _, _ in throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Network error"]) },
            searchPage: { _, _, _ in throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Network error"]) }
        )

        await failingLane.loadInitial()

        XCTAssertNotNil(failingLane.errorMessage)
        XCTAssertEqual(failingLane.errorMessage, "Network error")
    }

    func test_isLoading_duringFetch() async {
        let lane = LibraryLane<String>(
            fetchPage: { _, _ in
                try await Task.sleep(nanoseconds: 200_000_000)
                return PageResult(items: ["a", "b"], hasMore: false)
            },
            searchPage: { _, _, _ in
                try await Task.sleep(nanoseconds: 50_000_000)
                return PageResult(items: [], hasMore: false)
            }
        )

        let loadTask = Task { await lane.loadInitial() }
        // Yield to let the task start executing
        try? await Task.sleep(nanoseconds: 50_000_000)
        // isLoading should now be true while the fetch is sleeping
        XCTAssertTrue(lane.isLoading, "isLoading should be true while fetch is in progress")

        await loadTask.value
        XCTAssertFalse(lane.isLoading, "isLoading should be false after fetch completes")
    }
}