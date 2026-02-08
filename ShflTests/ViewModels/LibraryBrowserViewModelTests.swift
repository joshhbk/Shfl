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
        XCTAssertTrue(viewModel.isLoading)  // Starts true to show skeleton
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

    func test_performSearch_fetchesResults() async {
        let songs = [
            Song(id: "1", title: "Hello World", artist: "Artist", albumTitle: "Album", artworkURL: nil),
            Song(id: "2", title: "Goodbye", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        ]
        await mockService.setLibrarySongs(songs)

        await viewModel.performSearch(query: "Hello")

        XCTAssertEqual(viewModel.searchResults.count, 1)
        XCTAssertEqual(viewModel.searchResults.first?.title, "Hello World")
    }

    func test_performSearch_clearsResultsForEmptyQuery() async {
        let songs = [
            Song(id: "1", title: "Hello", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        ]
        await mockService.setLibrarySongs(songs)
        await viewModel.performSearch(query: "Hello")

        await viewModel.performSearch(query: "")

        XCTAssertTrue(viewModel.searchResults.isEmpty)
    }

    // MARK: - Autofill State Tests

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

        // Note: In real implementation we'd need to check loading state during execution
        // For now just verify it completes correctly
        await task.value

        XCTAssertEqual(viewModel.autofillState, .completed(count: 1))
    }

    func test_autofill_whilePlaying_rebuildsActiveQueue() async throws {
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

        let replaceCallCount = await mockService.replaceQueueCallCount
        XCTAssertEqual(replaceCallCount, 1, "Autofill while active should rebuild the transport queue")

        let queuedIds = Set(await mockService.lastQueuedSongs.map(\.id))
        XCTAssertEqual(queuedIds, Set(allSongs.map(\.id)))
    }
}
