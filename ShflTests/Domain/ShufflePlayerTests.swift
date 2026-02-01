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

    // MARK: - Dynamic Queue Updates

    func testAddSongDuringPlaybackRebuildsQueue() async throws {
        let song1 = Song(id: "1", title: "Song 1", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        try await player.addSong(song1)
        try await player.play()
        try await Task.sleep(nanoseconds: 100_000_000)

        await mockService.resetQueueTracking()

        let song2 = Song(id: "2", title: "Song 2", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        try await player.addSong(song2)
        try await Task.sleep(nanoseconds: 100_000_000)

        let callCount = await mockService.setQueueCallCount
        XCTAssertEqual(callCount, 1, "setQueue should be called when adding song during playback")
    }

    func testAddSongWhileStoppedDoesNotRebuildQueue() async throws {
        let song1 = Song(id: "1", title: "Song 1", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        try await player.addSong(song1)

        await mockService.resetQueueTracking()

        let song2 = Song(id: "2", title: "Song 2", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        try await player.addSong(song2)
        try await Task.sleep(nanoseconds: 100_000_000)

        let callCount = await mockService.setQueueCallCount
        XCTAssertEqual(callCount, 0, "setQueue should NOT be called when not playing")
    }

    func testPlayedSongsExcludedFromRebuild() async throws {
        let song1 = Song(id: "1", title: "Song 1", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        let song2 = Song(id: "2", title: "Song 2", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        try await player.addSong(song1)
        try await player.addSong(song2)
        try await player.play()
        try await Task.sleep(nanoseconds: 100_000_000)

        // Determine which song is currently playing (mock shuffles the queue)
        let state = await player.playbackState
        guard let firstSong = state.currentSong else {
            XCTFail("Expected a song to be playing")
            return
        }
        let secondSong = firstSong.id == song1.id ? song2 : song1

        // Simulate transition: first song finished, now playing second song
        await mockService.simulatePlaybackState(.playing(secondSong))
        try await Task.sleep(nanoseconds: 100_000_000)

        await mockService.resetQueueTracking()

        // Add new song
        let song3 = Song(id: "3", title: "Song 3", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        try await player.addSong(song3)
        try await Task.sleep(nanoseconds: 100_000_000)

        let lastQueued = await mockService.lastQueuedSongs
        let queuedIds = Set(lastQueued.map { $0.id })

        XCTAssertFalse(queuedIds.contains(firstSong.id), "Played song should be excluded")
        XCTAssertTrue(queuedIds.contains(secondSong.id), "Current song should be included")
        XCTAssertTrue(queuedIds.contains("3"), "New song3 should be included")
    }

    func testRemoveSongDuringPlaybackRebuildsQueue() async throws {
        let song1 = Song(id: "1", title: "Song 1", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        let song2 = Song(id: "2", title: "Song 2", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        try await player.addSong(song1)
        try await player.addSong(song2)
        try await player.play()
        try await Task.sleep(nanoseconds: 100_000_000)

        await mockService.resetQueueTracking()

        await player.removeSong(id: "2")
        try await Task.sleep(nanoseconds: 100_000_000)

        let callCount = await mockService.setQueueCallCount
        XCTAssertEqual(callCount, 1, "setQueue should be called when removing song during playback")

        let lastQueued = await mockService.lastQueuedSongs
        let queuedIds = lastQueued.map { $0.id }
        XCTAssertFalse(queuedIds.contains("2"), "Removed song should not be in queue")
    }

    func testRemoveCurrentlyPlayingSongContinuesPlayback() async throws {
        let song1 = Song(id: "1", title: "Song 1", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        let song2 = Song(id: "2", title: "Song 2", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        try await player.addSong(song1)
        try await player.addSong(song2)
        try await player.play()
        try await Task.sleep(nanoseconds: 100_000_000)

        // Remove currently playing song
        let currentSongId = await player.playbackState.currentSongId
        await player.removeSong(id: currentSongId!)
        try await Task.sleep(nanoseconds: 100_000_000)

        // Playback should still be active (song finishes naturally)
        let state = await player.playbackState
        XCTAssertTrue(state.isActive, "Playback should continue after removing current song")

        // Song should be removed from songs list
        let containsSong = await player.containsSong(id: currentSongId!)
        XCTAssertFalse(containsSong, "Removed song should not be in songs list")
    }

    func testPlayAppliesShuffleAlgorithm() async throws {
        // Set algorithm to noRepeat (default)
        UserDefaults.standard.set("noRepeat", forKey: "shuffleAlgorithm")

        let songs = (1...5).map { i in
            Song(id: "\(i)", title: "Song \(i)", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        }

        for song in songs {
            try await player.addSong(song)
        }

        try await player.play()

        // Verify queue was set (shuffler was applied)
        let queuedSongs = await mockService.lastQueuedSongs
        XCTAssertEqual(queuedSongs.count, 5)
        XCTAssertEqual(Set(queuedSongs.map(\.id)), Set(songs.map(\.id)))
    }

    func testPlayClearsHistory() async throws {
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

        // Simulate song transition to build history
        await mockService.simulatePlaybackState(.playing(otherSong))
        try await Task.sleep(nanoseconds: 100_000_000)

        var playedIds = await player.playedSongIdsForTesting
        XCTAssertTrue(playedIds.contains(currentSong.id), "History should contain played song")

        // Pause and play again - should clear history
        await player.pause()
        try await Task.sleep(nanoseconds: 100_000_000)
        try await player.play()
        try await Task.sleep(nanoseconds: 100_000_000)

        playedIds = await player.playedSongIdsForTesting
        XCTAssertTrue(playedIds.isEmpty, "History should be cleared on fresh play")
    }

    // MARK: - Queue Rebuild with Shuffle Algorithm

    func testAddSongDuringPlaybackAppliesShuffleAlgorithm() async throws {
        UserDefaults.standard.set("artistSpacing", forKey: "shuffleAlgorithm")

        let song1 = Song(id: "1", title: "Song 1", artist: "Artist A", albumTitle: "Album", artworkURL: nil)
        try await player.addSong(song1)
        try await player.play()
        try await Task.sleep(nanoseconds: 100_000_000)

        await mockService.resetQueueTracking()

        let song2 = Song(id: "2", title: "Song 2", artist: "Artist B", albumTitle: "Album", artworkURL: nil)
        try await player.addSong(song2)
        try await Task.sleep(nanoseconds: 100_000_000)

        let usedAlgorithm = await player.lastUsedAlgorithm
        XCTAssertEqual(usedAlgorithm, .artistSpacing, "Shuffle algorithm should be applied on queue rebuild")
    }

    func testAddSongDuringPlaybackCallsPlay() async throws {
        let song1 = Song(id: "1", title: "Song 1", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        try await player.addSong(song1)
        try await player.play()
        try await Task.sleep(nanoseconds: 100_000_000)

        await mockService.resetQueueTracking()

        let song2 = Song(id: "2", title: "Song 2", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        try await player.addSong(song2)
        try await Task.sleep(nanoseconds: 100_000_000)

        let playCount = await mockService.playCallCount
        XCTAssertEqual(playCount, 1, "play() should be called after setQueue during rebuild")
    }

    // MARK: - Playback Position Preservation

    func testAddSongPreservesPlaybackPosition() async throws {
        let song1 = Song(id: "1", title: "Song 1", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        try await player.addSong(song1)
        try await player.play()
        try await Task.sleep(nanoseconds: 100_000_000)

        // Simulate being 45 seconds into the song
        await mockService.setMockPlaybackTime(45.0)
        await mockService.resetQueueTracking()

        let song2 = Song(id: "2", title: "Song 2", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        try await player.addSong(song2)
        try await Task.sleep(nanoseconds: 100_000_000)

        let seekCount = mockService.seekCallCount
        let seekTime = mockService.lastSeekTime
        XCTAssertEqual(seekCount, 1, "seek() should be called to restore position")
        XCTAssertEqual(seekTime, 45.0, "Should seek to saved playback time")
    }

    func testRemoveCurrentSongDoesNotPreservePosition() async throws {
        let song1 = Song(id: "1", title: "Song 1", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        let song2 = Song(id: "2", title: "Song 2", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        try await player.addSong(song1)
        try await player.addSong(song2)
        try await player.play()
        try await Task.sleep(nanoseconds: 100_000_000)

        await mockService.setMockPlaybackTime(45.0)
        await mockService.resetQueueTracking()

        let currentSongId = await player.playbackState.currentSongId!
        await player.removeSong(id: currentSongId)
        try await Task.sleep(nanoseconds: 100_000_000)

        let seekCount = mockService.seekCallCount
        XCTAssertEqual(seekCount, 0, "seek() should NOT be called when removing current song")
    }

    // MARK: - Batch Add Operation

    func testAddSongsWithQueueRebuildCallsSetQueueOnce() async throws {
        let song1 = Song(id: "1", title: "Song 1", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        try await player.addSong(song1)
        try await player.play()
        try await Task.sleep(nanoseconds: 100_000_000)

        await mockService.resetQueueTracking()

        let newSongs = (2...5).map { i in
            Song(id: "\(i)", title: "Song \(i)", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        }
        try await player.addSongsWithQueueRebuild(newSongs)
        try await Task.sleep(nanoseconds: 100_000_000)

        let callCount = await mockService.setQueueCallCount
        XCTAssertEqual(callCount, 1, "Batch add should only call setQueue once")
    }

    func testAddSongsWithQueueRebuildIncludesAllSongs() async throws {
        let song1 = Song(id: "1", title: "Song 1", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        try await player.addSong(song1)
        try await player.play()
        try await Task.sleep(nanoseconds: 100_000_000)

        await mockService.resetQueueTracking()

        let newSongs = (2...4).map { i in
            Song(id: "\(i)", title: "Song \(i)", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        }
        try await player.addSongsWithQueueRebuild(newSongs)
        try await Task.sleep(nanoseconds: 100_000_000)

        let queuedIds = Set(await mockService.lastQueuedSongs.map(\.id))
        XCTAssertTrue(queuedIds.contains("1"), "Original song should be in queue")
        XCTAssertTrue(queuedIds.contains("2"), "New song 2 should be in queue")
        XCTAssertTrue(queuedIds.contains("3"), "New song 3 should be in queue")
        XCTAssertTrue(queuedIds.contains("4"), "New song 4 should be in queue")
    }
}
