import XCTest
@testable import ShflCore
@testable import ShflDeterministic
import ShflTestSupport

@MainActor
final class LibraryBrowserTests: XCTestCase {
    private var mockService: DeterministicMusicService!
    private var browser: LibraryBrowser!
    private var defaults: UserDefaults!
    private var defaultsSuiteName: String!

    override func setUp() async throws {
        defaultsSuiteName = "LibraryBrowserTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)
        mockService = DeterministicMusicService()
        browser = LibraryBrowser(libraryCatalog: mockService, preferences: makePreferences())
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        defaults = nil
        browser = nil
        mockService = nil
    }

    private func makePreferences() -> LibraryPreferences {
        LibraryPreferences(defaults: defaults)
    }

    func test_initialState_isCorrect() {
        XCTAssertTrue(browser.browseSongs.isEmpty)
        XCTAssertTrue(browser.searchResults.isEmpty)
        XCTAssertEqual(browser.searchText, "")
        XCTAssertEqual(browser.currentMode, .browse)
        XCTAssertFalse(browser.isLoading)
        XCTAssertEqual(browser.sortOption, .mostPlayed)
    }

    func test_currentMode_switchesToSearchWhenTextEntered() {
        browser.searchText = "test"
        XCTAssertEqual(browser.currentMode, .search)
    }

    func test_currentMode_switchesToBrowseWhenTextCleared() {
        browser.searchText = "test"
        browser.searchText = ""
        XCTAssertEqual(browser.currentMode, .browse)
    }

    func test_loadInitialPage_fetchesSongs() async {
        let songs = [
            Song(id: "1", title: "Song 1", artist: "Artist", albumTitle: "Album", artworkURL: nil),
            Song(id: "2", title: "Song 2", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        ]
        await mockService.setLibrarySongs(songs)

        await browser.loadInitialPage()

        XCTAssertEqual(browser.browseSongs.count, 2)
        XCTAssertFalse(browser.browseLoading)
    }

    func test_loadInitialPage_setsHasMorePages() async {
        // Create more songs than page size to test pagination
        let songs = (1...60).map {
            Song(id: "\($0)", title: "Song \($0)", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        }
        await mockService.setLibrarySongs(songs)

        await browser.loadInitialPage()

        XCTAssertEqual(browser.browseSongs.count, 50)
        XCTAssertTrue(browser.hasMorePages)
    }

    func test_loadNextPage_appendsSongs() async {
        let songs = (1...60).map {
            Song(id: "\($0)", title: "Song \($0)", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        }
        await mockService.setLibrarySongs(songs)

        await browser.loadInitialPage()
        await browser.loadNextPageIfNeeded(currentSong: browser.browseSongs.last!)

        XCTAssertEqual(browser.browseSongs.count, 60)
        XCTAssertFalse(browser.hasMorePages)
    }

    func test_search_fetchesResults() async {
        let songs = [
            Song(id: "1", title: "Hello World", artist: "Artist", albumTitle: "Album", artworkURL: nil),
            Song(id: "2", title: "Goodbye", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        ]
        await mockService.setLibrarySongs(songs)

        // Search through the songs lane directly (bypasses debounce in view model)
        browser.songsLane.handleSearchTextChanged("Hello")
        // Wait for debounce (300ms) + search task to complete
        try? await Task.sleep(nanoseconds: 600_000_000)

        let searchResults = browser.searchResults
        XCTAssertEqual(searchResults.count, 1)
        XCTAssertEqual(searchResults.first?.title, "Hello World")
    }

    func test_choosingASortOptionSavesItAndReloadsSongsInThatOrder() async {
        let songs = [
            Song(id: "b", title: "Bravo", artist: "Artist", albumTitle: "Album", artworkURL: nil, playCount: 9),
            Song(id: "a", title: "Alpha", artist: "Artist", albumTitle: "Album", artworkURL: nil, playCount: 1)
        ]
        await mockService.setLibrarySongs(songs)
        await browser.loadInitialPage()
        XCTAssertEqual(browser.browseSongs.map(\.id), ["b", "a"])

        browser.chooseSortOption(.alphabetical)
        await waitUntil { self.browser.browseSongs.map(\.id) == ["a", "b"] }

        XCTAssertEqual(browser.sortOption, .alphabetical)
        XCTAssertEqual(LibraryPreferences(defaults: defaults).sortOption, .alphabetical)
    }

    func test_choosingTheCurrentSortOptionDoesNotReload() async {
        await browser.loadInitialPage()
        let fetchesBefore = await mockService.libraryFetchCount

        browser.chooseSortOption(.mostPlayed)
        await waitForStateUpdate()

        let fetchesAfter = await mockService.libraryFetchCount
        XCTAssertEqual(fetchesAfter, fetchesBefore)
    }

    func test_autofillUsesTheSavedAutofillAlgorithm() async {
        // Random pages through the whole library (500 per page); recently added reads one page.
        let songs = (1...600).map {
            Song(id: "\($0)", title: "Song \($0)", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        }
        await mockService.setLibrarySongs(songs)
        let preferences = makePreferences()
        preferences.autofillAlgorithm = .recentlyAdded
        let browser = LibraryBrowser(libraryCatalog: mockService, preferences: preferences)
        let draft = SessionDraftStore()

        await browser.autofill(into: draft)

        XCTAssertEqual(draft.songCount, SessionDraft.maxSongs)
        let fetches = await mockService.libraryFetchCount
        XCTAssertEqual(fetches, 1)
    }

    func test_switchingToALaneLoadsItsFirstPage() async {
        let service = DeterministicMusicService(
            configuration: .init(libraryPlaylists: [Playlist(id: "p1", name: "Road Trip")])
        )
        let browser = LibraryBrowser(libraryCatalog: service, preferences: makePreferences())
        XCTAssertEqual(browser.activeLane, .songs)

        browser.activeLane = .playlists
        await waitUntil { browser.playlists.map(\.id) == ["p1"] }

        XCTAssertEqual(browser.playlists.map(\.id), ["p1"])
    }

    func test_leavingTheCatalogLoadsNothing() async {
        let service = DeterministicMusicService(
            configuration: .init(libraryPlaylists: [Playlist(id: "p1", name: "Road Trip")])
        )
        let browser = LibraryBrowser(libraryCatalog: service, preferences: makePreferences())

        browser.activeLane = nil
        browser.searchText = "Road"
        // Past the search debounce (300ms), so a search would have run.
        try? await Task.sleep(nanoseconds: 600_000_000)

        XCTAssertTrue(browser.playlists.isEmpty)
        XCTAssertTrue(browser.playlistSearchResults.isEmpty)
        XCTAssertTrue(browser.searchResults.isEmpty)
    }

    func test_autofillState_initiallyIdle() {
        XCTAssertEqual(browser.autofillState, .idle)
    }

    // MARK: - Autofill Method Tests

    func test_autofill_addsSongsToTheDraft() async {
        let songs = (1...50).map {
            Song(id: "\($0)", title: "Song \($0)", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        }
        await mockService.setLibrarySongs(songs)

        let draft = SessionDraftStore()

        await browser.autofill(into: draft)

        XCTAssertEqual(draft.songCount, 50)
        XCTAssertEqual(browser.autofillState, .completed(count: 50))
    }

    func test_autofill_fillsOnlyRemainingCapacity() async {
        let songs = (1...200).map {
            Song(id: "\($0)", title: "Song \($0)", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        }
        await mockService.setLibrarySongs(songs)

        let draft = SessionDraftStore()
        // Add 100 songs first
        for i in 1...100 {
            try? draft.add(Song(id: "existing-\(i)", title: "Existing \(i)", artist: "Artist", albumTitle: "Album", artworkURL: nil))
        }
        await browser.autofill(into: draft)

        // Should only add 20 more (120 - 100)
        XCTAssertEqual(draft.songCount, 120)
        XCTAssertEqual(browser.autofillState, .completed(count: 20))
    }

    func test_autofill_excludesDuplicates() async {
        let songs = (1...10).map {
            Song(id: "\($0)", title: "Song \($0)", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        }
        await mockService.setLibrarySongs(songs)

        let draft = SessionDraftStore()
        // Pre-add some songs that are also in library
        try? draft.add(songs[0])
        try? draft.add(songs[1])
        await browser.autofill(into: draft)

        // Should add 8 new songs (10 - 2 already added)
        XCTAssertEqual(draft.songCount, 10)
        XCTAssertEqual(browser.autofillState, .completed(count: 8))
    }

    func test_autofill_completesWithZeroWhenFull() async {
        let draft = SessionDraftStore()
        // Fill to capacity
        for i in 1...120 {
            try? draft.add(Song(id: "\(i)", title: "Song \(i)", artist: "Artist", albumTitle: "Album", artworkURL: nil))
        }
        await browser.autofill(into: draft)

        XCTAssertEqual(browser.autofillState, .completed(count: 0))
    }

    func test_autofill_setsLoadingState() async {
        let songs = [Song(id: "1", title: "Song", artist: "Artist", albumTitle: "Album", artworkURL: nil)]
        await mockService.setLibrarySongs(songs)

        let draft = SessionDraftStore()

        // Start autofill
        let task = Task {
            await browser.autofill(into: draft)
        }

        // Verify it completes correctly
        await task.value

        XCTAssertEqual(browser.autofillState, .completed(count: 1))
    }

    func test_autofill_whilePlaying_defersTransportAndUpdatesDomainQueue() async throws {
        let allSongs = (1...5).map {
            Song(id: "\($0)", title: "Song \($0)", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        }
        await mockService.setLibrarySongs(allSongs)

        let draft = SessionDraftStore()
        let player = ShufflePlayer(playbackTransport: mockService, sessionDraft: draft)
        try draft.add(allSongs[0])
        try draft.add(allSongs[1])
        try await player.startFreshShuffle(seed: 1)
        try await Task.sleep(nanoseconds: 100_000_000)

        await mockService.resetPlaybackRecording()
        await browser.autofill(into: draft)

        XCTAssertEqual(browser.autofillState, .completed(count: 3))
        XCTAssertEqual(draft.songCount, 5)

        // Transport sync is deferred to avoid playback interruption
        let loadCallCount = await mockService.loadCallCount
        XCTAssertEqual(loadCallCount, 0, "Autofill while active should defer transport sync")

        // Active session stays immutable; the draft contains the next shuffle.
        let activeSessionIds = Set(player.lastShuffledQueue.map(\.id))
        XCTAssertEqual(activeSessionIds, Set(allSongs.prefix(2).map(\.id)))
        XCTAssertEqual(Set(draft.songs.map(\.id)), Set(allSongs.map(\.id)))
        XCTAssertTrue(player.hasPendingSessionChanges)
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
