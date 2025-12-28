import XCTest
@testable import Shfl

final class AppFlowTests: XCTestCase {
    func testFullPlaybackFlow() async throws {
        let mockService = MockMusicService()
        let player = await ShufflePlayer(musicService: mockService)

        // Add songs
        let songs = (1...5).map { i in
            Song(id: "\(i)", title: "Song \(i)", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        }

        for song in songs {
            try await player.addSong(song)
        }

        let songCount = await player.songCount
        XCTAssertEqual(songCount, 5)

        // Play
        try await player.play()
        try await Task.sleep(nanoseconds: 100_000_000)

        var state = await player.playbackState
        XCTAssertTrue(state.isPlaying)

        // Skip
        try await player.skipToNext()
        try await Task.sleep(nanoseconds: 100_000_000)

        state = await player.playbackState
        XCTAssertTrue(state.isPlaying)

        // Pause
        await player.pause()
        try await Task.sleep(nanoseconds: 100_000_000)

        state = await player.playbackState
        if case .paused = state {
            // Expected
        } else {
            XCTFail("Expected paused state")
        }

        // Resume
        try await player.togglePlayback()
        try await Task.sleep(nanoseconds: 100_000_000)

        state = await player.playbackState
        XCTAssertTrue(state.isPlaying)
    }

    func testCapacityEnforcement() async throws {
        let mockService = MockMusicService()
        let player = await ShufflePlayer(musicService: mockService)

        // Fill to capacity
        for i in 0..<120 {
            let song = Song(id: "\(i)", title: "Song \(i)", artist: "Artist", albumTitle: "Album", artworkURL: nil)
            try await player.addSong(song)
        }

        let songCount = await player.songCount
        XCTAssertEqual(songCount, 120)

        let remaining = await player.remainingCapacity
        XCTAssertEqual(remaining, 0)

        // Try to exceed
        let extraSong = Song(id: "extra", title: "Extra", artist: "Artist", albumTitle: "Album", artworkURL: nil)

        do {
            try await player.addSong(extraSong)
            XCTFail("Should throw capacity error")
        } catch ShufflePlayerError.capacityReached {
            // Expected
        }
    }

    func testSongAdditionAndRemoval() async throws {
        let mockService = MockMusicService()
        let player = await ShufflePlayer(musicService: mockService)

        let song1 = Song(id: "1", title: "Song 1", artist: "Artist 1", albumTitle: "Album", artworkURL: nil)
        let song2 = Song(id: "2", title: "Song 2", artist: "Artist 2", albumTitle: "Album", artworkURL: nil)

        // Add songs
        try await player.addSong(song1)
        try await player.addSong(song2)

        var songCount = await player.songCount
        XCTAssertEqual(songCount, 2)

        // Verify contains
        var contains1 = await player.containsSong(id: "1")
        var contains2 = await player.containsSong(id: "2")
        XCTAssertTrue(contains1)
        XCTAssertTrue(contains2)

        // Remove one
        await player.removeSong(id: "1")

        songCount = await player.songCount
        XCTAssertEqual(songCount, 1)

        contains1 = await player.containsSong(id: "1")
        contains2 = await player.containsSong(id: "2")
        XCTAssertFalse(contains1)
        XCTAssertTrue(contains2)

        // Remove all
        await player.removeAllSongs()

        songCount = await player.songCount
        XCTAssertEqual(songCount, 0)
    }

    func testDuplicateSongPrevention() async throws {
        let mockService = MockMusicService()
        let player = await ShufflePlayer(musicService: mockService)

        let song = Song(id: "1", title: "Song 1", artist: "Artist", albumTitle: "Album", artworkURL: nil)

        // Add same song twice
        try await player.addSong(song)
        try await player.addSong(song)

        // Should only have one
        let songCount = await player.songCount
        XCTAssertEqual(songCount, 1)
    }

    func testDirectAddFromPlayerView() async throws {
        // This tests the navigation flow: PlayerView -> "+" -> SongPickerView
        // The actual UI navigation is tested via UI tests, but we can verify the state management

        let mockService = MockMusicService()
        let player = await ShufflePlayer(musicService: mockService)

        let song = Song(id: "1", title: "Test Song", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        try await player.addSong(song)

        let songCount = await player.songCount
        XCTAssertEqual(songCount, 1)

        // Verify song can be removed
        await player.removeSong(id: "1")
        let afterRemove = await player.songCount
        XCTAssertEqual(afterRemove, 0)
    }

    @MainActor
    func testUndoManagerIntegration() async throws {
        let undoManager = SongUndoManager()
        let song = Song(id: "1", title: "Test", artist: "Artist", albumTitle: "Album", artworkURL: nil)

        // Record an add action
        undoManager.recordAction(.added, song: song)

        let state = undoManager.currentState
        XCTAssertNotNil(state)
        XCTAssertEqual(state?.action, .added)
    }
}
