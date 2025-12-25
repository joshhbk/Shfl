import XCTest
import SwiftData
@testable import Shfl

final class SongRepositoryTests: XCTestCase {
    var container: ModelContainer!
    var repository: SongRepository!

    @MainActor
    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: PersistedSong.self, configurations: config)
        repository = SongRepository(modelContext: container.mainContext)
    }

    override func tearDown() {
        container = nil
        repository = nil
    }

    @MainActor
    func testSaveAndLoadSongs() async throws {
        let songs = [
            Song(id: "1", title: "Song 1", artist: "Artist 1", albumTitle: "Album 1", artworkURL: nil),
            Song(id: "2", title: "Song 2", artist: "Artist 2", albumTitle: "Album 2", artworkURL: nil)
        ]

        try repository.saveSongs(songs)
        let loaded = try repository.loadSongs()

        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded[0].id, "1")
        XCTAssertEqual(loaded[1].id, "2")
    }

    @MainActor
    func testSaveSongReplacesExisting() async throws {
        let songs1 = [Song(id: "1", title: "Original", artist: "A", albumTitle: "B", artworkURL: nil)]
        try repository.saveSongs(songs1)

        let songs2 = [Song(id: "2", title: "New", artist: "C", albumTitle: "D", artworkURL: nil)]
        try repository.saveSongs(songs2)

        let loaded = try repository.loadSongs()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].id, "2")
    }

    @MainActor
    func testClearSongs() async throws {
        let songs = [Song(id: "1", title: "Song", artist: "A", albumTitle: "B", artworkURL: nil)]
        try repository.saveSongs(songs)
        try repository.clearSongs()

        let loaded = try repository.loadSongs()
        XCTAssertTrue(loaded.isEmpty)
    }
}
