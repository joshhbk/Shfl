import XCTest
@testable import Shfl

final class ShufflePlayerTests: XCTestCase {
    var mockService: MockMusicService!
    var player: ShufflePlayer!

    override func setUp() async throws {
        mockService = MockMusicService()
        player = await ShufflePlayer(musicService: mockService)
    }

    // MARK: - Song Management

    func testInitialStateIsEmpty() async {
        let songCount = await player.songCount
        XCTAssertEqual(songCount, 0)
    }

    func testAddSong() async throws {
        let song = Song(id: "1", title: "Test", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        try await player.addSong(song)

        let songCount = await player.songCount
        XCTAssertEqual(songCount, 1)
    }

    func testAddSongRespectsLimit() async throws {
        for i in 0..<120 {
            let song = Song(id: "\(i)", title: "Song \(i)", artist: "Artist", albumTitle: "Album", artworkURL: nil)
            try await player.addSong(song)
        }

        let extraSong = Song(id: "extra", title: "Extra", artist: "Artist", albumTitle: "Album", artworkURL: nil)

        do {
            try await player.addSong(extraSong)
            XCTFail("Should have thrown capacity error")
        } catch ShufflePlayerError.capacityReached {
            // Expected
        }

        let songCount = await player.songCount
        XCTAssertEqual(songCount, 120)
    }

    func testRemoveSong() async throws {
        let song = Song(id: "1", title: "Test", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        try await player.addSong(song)
        await player.removeSong(id: "1")

        let songCount = await player.songCount
        XCTAssertEqual(songCount, 0)
    }

    func testRemoveAllSongs() async throws {
        for i in 0..<5 {
            let song = Song(id: "\(i)", title: "Song \(i)", artist: "Artist", albumTitle: "Album", artworkURL: nil)
            try await player.addSong(song)
        }

        await player.removeAllSongs()

        let songCount = await player.songCount
        XCTAssertEqual(songCount, 0)
    }

    // MARK: - Playback

    func testPlayWithNoSongsDoesNothing() async throws {
        try await player.play()
        // Should not crash, state remains empty
    }

    func testPlayStartsPlayback() async throws {
        let song = Song(id: "1", title: "Test", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        try await player.addSong(song)
        try await player.play()

        // Give async stream time to update
        try await Task.sleep(nanoseconds: 100_000_000)

        let state = await player.playbackState
        XCTAssertTrue(state.isPlaying)
    }

    func testPause() async throws {
        let song = Song(id: "1", title: "Test", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        try await player.addSong(song)
        try await player.play()
        try await Task.sleep(nanoseconds: 100_000_000)
        await player.pause()
        try await Task.sleep(nanoseconds: 100_000_000)

        let state = await player.playbackState
        if case .paused = state {
            // Expected
        } else {
            XCTFail("Expected paused state, got \(state)")
        }
    }

    func testSkipToNext() async throws {
        let song1 = Song(id: "1", title: "Song 1", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        let song2 = Song(id: "2", title: "Song 2", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        try await player.addSong(song1)
        try await player.addSong(song2)
        try await player.play()
        try await Task.sleep(nanoseconds: 100_000_000)
        try await player.skipToNext()
        try await Task.sleep(nanoseconds: 100_000_000)

        let state = await player.playbackState
        XCTAssertTrue(state.isPlaying)
    }

    func testTogglePlayback() async throws {
        let song = Song(id: "1", title: "Test", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        try await player.addSong(song)

        // First toggle starts playback
        try await player.togglePlayback()
        try await Task.sleep(nanoseconds: 100_000_000)
        var state = await player.playbackState
        XCTAssertTrue(state.isPlaying)

        // Second toggle pauses
        try await player.togglePlayback()
        try await Task.sleep(nanoseconds: 100_000_000)
        state = await player.playbackState
        if case .paused = state {
            // Expected
        } else {
            XCTFail("Expected paused state")
        }

        // Third toggle resumes
        try await player.togglePlayback()
        try await Task.sleep(nanoseconds: 100_000_000)
        state = await player.playbackState
        XCTAssertTrue(state.isPlaying)
    }

    // MARK: - Play History Tracking

    func testSongTransitionAddsToHistory() async throws {
        let song1 = Song(id: "1", title: "Song 1", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        let song2 = Song(id: "2", title: "Song 2", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        try await player.addSong(song1)
        try await player.addSong(song2)
        try await player.play()
        try await Task.sleep(nanoseconds: 100_000_000)

        // Determine which song is currently playing (mock shuffles the queue)
        let state = await player.playbackState
        guard let currentSong = state.currentSong else {
            XCTFail("Expected a song to be playing")
            return
        }
        let otherSong = currentSong.id == song1.id ? song2 : song1

        // Simulate song transition to the other song
        await mockService.simulatePlaybackState(.playing(otherSong))
        try await Task.sleep(nanoseconds: 100_000_000)

        let playedIds = await player.playedSongIdsForTesting
        XCTAssertTrue(playedIds.contains(currentSong.id), "First song should be in history after transition")
        XCTAssertFalse(playedIds.contains(otherSong.id), "Current song should not be in history yet")
    }

    func testHistoryClearedOnStop() async throws {
        let song1 = Song(id: "1", title: "Song 1", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        let song2 = Song(id: "2", title: "Song 2", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        try await player.addSong(song1)
        try await player.addSong(song2)
        try await player.play()
        try await Task.sleep(nanoseconds: 100_000_000)

        // Determine which song is currently playing (mock shuffles the queue)
        let state = await player.playbackState
        guard let currentSong = state.currentSong else {
            XCTFail("Expected a song to be playing")
            return
        }
        let otherSong = currentSong.id == song1.id ? song2 : song1

        // Simulate song transition then stop
        await mockService.simulatePlaybackState(.playing(otherSong))
        try await Task.sleep(nanoseconds: 100_000_000)
        await mockService.simulatePlaybackState(.stopped)
        try await Task.sleep(nanoseconds: 100_000_000)

        let playedIds = await player.playedSongIdsForTesting
        XCTAssertTrue(playedIds.isEmpty)
    }

    func testHistoryClearedOnEmpty() async throws {
        let song = Song(id: "1", title: "Song 1", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        try await player.addSong(song)
        try await player.play()
        try await Task.sleep(nanoseconds: 100_000_000)

        await mockService.simulatePlaybackState(.empty)
        try await Task.sleep(nanoseconds: 100_000_000)

        let playedIds = await player.playedSongIdsForTesting
        XCTAssertTrue(playedIds.isEmpty)
    }
}
