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
        XCTAssertFalse(viewModel.isLoading)
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
}
