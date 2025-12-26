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
}
