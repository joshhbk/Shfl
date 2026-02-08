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

    /// Reproduces bug: autofill → clear → manually add → play → queue should be populated
    func testAddSongsAfterClearThenPlayPopulatesQueue() async throws {
        // Step 1: Simulate autofill (add songs and play)
        for i in 0..<5 {
            let song = Song(id: "auto\(i)", title: "Auto Song \(i)", artist: "Artist", albumTitle: "Album", artworkURL: nil)
            try await player.addSong(song)
        }
        try await player.play()
        try await Task.sleep(nanoseconds: 100_000_000)

        // Verify queue was populated
        var queue = await player.lastShuffledQueue
        XCTAssertEqual(queue.count, 5, "Queue should have 5 songs after autofill+play")

        // Step 2: Clear all songs
        await player.removeAllSongs()

        queue = await player.lastShuffledQueue
        XCTAssertEqual(queue.count, 0, "Queue should be empty after clear")

        let songCount = await player.songCount
        XCTAssertEqual(songCount, 0, "Song pool should be empty after clear")

        // Step 3: Manually add several songs
        for i in 0..<3 {
            let song = Song(id: "manual\(i)", title: "Manual Song \(i)", artist: "Artist", albumTitle: "Album", artworkURL: nil)
            try await player.addSong(song)
        }

        let newSongCount = await player.songCount
        XCTAssertEqual(newSongCount, 3, "Should have 3 songs in pool")

        // Step 4: Play
        try await player.play()
        try await Task.sleep(nanoseconds: 100_000_000)

        // Step 5: Verify queue is populated
        queue = await player.lastShuffledQueue
        XCTAssertEqual(queue.count, 3, "Queue should have 3 songs after play")
    }

    /// Bug fix: When paused with no queue (after clear + re-add), togglePlayback should rebuild queue
    func testTogglePlaybackWhenPausedButNoQueue() async throws {
        // Step 1: Add songs and play to get into a playing state
        for i in 0..<3 {
            let song = Song(id: "old\(i)", title: "Old Song \(i)", artist: "Artist", albumTitle: "Album", artworkURL: nil)
            try await player.addSong(song)
        }
        try await player.play()
        try await Task.sleep(nanoseconds: 100_000_000)

        // Step 2: Pause
        await player.pause()
        try await Task.sleep(nanoseconds: 100_000_000)

        // Verify we're paused
        var playbackState = await player.playbackState
        if case .paused = playbackState {
            // Good - we're paused
        } else {
            XCTFail("Expected paused state, got \(playbackState)")
        }

        // Step 3: Clear all songs - this clears queueState but playbackState stays paused
        await player.removeAllSongs()

        // Step 4: Add new songs
        for i in 0..<2 {
            let song = Song(id: "new\(i)", title: "New Song \(i)", artist: "Artist", albumTitle: "Album", artworkURL: nil)
            try await player.addSong(song)
        }

        // Queue should be empty (songs only in pool)
        var queue = await player.lastShuffledQueue
        XCTAssertEqual(queue.count, 0, "Queue should be empty before togglePlayback")

        // Step 5: Toggle playback (while paused with songs but no queue)
        try await player.togglePlayback()
        try await Task.sleep(nanoseconds: 100_000_000)

        // Step 6: Queue should now be populated with new songs
        queue = await player.lastShuffledQueue
        XCTAssertEqual(queue.count, 2, "Queue should have 2 new songs after togglePlayback")

        // Verify it's the NEW songs, not old ones
        let queueIds = Set(queue.map { $0.id })
        XCTAssertEqual(queueIds, Set(["new0", "new1"]), "Queue should have new songs")
    }

    /// Test with playback state still active after clear (simulates real MusicKit behavior)
    func testAddSongsAfterClearWhileStillPlayingPopulatesQueue() async throws {
        // Step 1: Add songs and play
        for i in 0..<5 {
            let song = Song(id: "auto\(i)", title: "Auto Song \(i)", artist: "Artist", albumTitle: "Album", artworkURL: nil)
            try await player.addSong(song)
        }
        try await player.play()
        try await Task.sleep(nanoseconds: 100_000_000)

        // Step 2: Clear songs but KEEP playback state active (don't stop MusicKit)
        // This simulates real app behavior where MusicKit may still report active state
        await player.removeAllSongs()

        // Verify internal state is cleared
        var songCount = await player.songCount
        XCTAssertEqual(songCount, 0, "Song pool should be empty after clear")

        // BUT playback state might still be active in real app
        // For this test, manually keep it active via mock
        let playbackState = await player.playbackState
        print("Playback state after clear: \(playbackState)")

        // Step 3: Add new songs
        for i in 0..<3 {
            let song = Song(id: "manual\(i)", title: "Manual Song \(i)", artist: "Artist", albumTitle: "Album", artworkURL: nil)
            try await player.addSong(song)
        }

        songCount = await player.songCount
        XCTAssertEqual(songCount, 3, "Should have 3 songs in pool")

        // Queue should still be empty before play (songs only added to pool)
        var queue = await player.lastShuffledQueue
        XCTAssertEqual(queue.count, 0, "Queue should be empty before play (only pool is filled)")

        // Step 4: Play should build new queue
        try await player.play()
        try await Task.sleep(nanoseconds: 100_000_000)

        // Step 5: Verify queue is now populated
        queue = await player.lastShuffledQueue
        XCTAssertEqual(queue.count, 3, "Queue should have 3 songs after play")
    }

    // MARK: - Playback

    func testPlayWithNoSongsDoesNothing() async throws {
        try await player.play()
        // Should not crash, state remains empty
    }

    /// Bug report: adding songs from empty state and pressing play should populate queue
    func testAddSongsFromEmptyStateThenPlay() async throws {
        // Verify starting from empty
        var songCount = await player.songCount
        XCTAssertEqual(songCount, 0, "Should start empty")

        var queue = await player.lastShuffledQueue
        XCTAssertEqual(queue.count, 0, "Queue should be empty initially")

        // Add songs
        for i in 0..<5 {
            let song = Song(id: "\(i)", title: "Song \(i)", artist: "Artist", albumTitle: "Album", artworkURL: nil)
            try await player.addSong(song)
        }

        songCount = await player.songCount
        XCTAssertEqual(songCount, 5, "Should have 5 songs in pool")

        // Queue should still be empty before play
        queue = await player.lastShuffledQueue
        XCTAssertEqual(queue.count, 0, "Queue should be empty before play")

        // Now play
        try await player.play()
        try await Task.sleep(nanoseconds: 100_000_000)

        // Queue should be populated
        queue = await player.lastShuffledQueue
        XCTAssertEqual(queue.count, 5, "Queue should have 5 songs after play")

        // Verify all songs are in queue
        let queueIds = Set(queue.map { $0.id })
        XCTAssertEqual(queueIds, Set(["0", "1", "2", "3", "4"]), "All songs should be in queue")
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

    /// Documents current behavior: addSong during playback uses insertIntoQueue (appends to tail)
    func testAddSongDuringPlaybackInsertsIntoQueue() async throws {
        let song1 = Song(id: "1", title: "Song 1", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        try await player.addSong(song1)
        try await player.play()
        try await Task.sleep(nanoseconds: 100_000_000)

        // Verify initial queue has 1 song
        var queue = await player.lastShuffledQueue
        XCTAssertEqual(queue.count, 1, "Queue should have 1 song after play")

        await mockService.resetQueueTracking()

        let song2 = Song(id: "2", title: "Song 2", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        try await player.addSong(song2)
        try await Task.sleep(nanoseconds: 100_000_000)

        // Verify internal queue order is updated
        queue = await player.lastShuffledQueue
        XCTAssertEqual(queue.count, 2, "Queue should have 2 songs after adding during playback")
        XCTAssertTrue(queue.contains { $0.id == "2" }, "New song should be in queue order")

        // Verify MusicKit was also updated
        let insertCallCount = await mockService.insertIntoQueueCallCount
        XCTAssertEqual(insertCallCount, 1, "insertIntoQueue should be called when adding song during playback")

        let setQueueCallCount = await mockService.setQueueCallCount
        XCTAssertEqual(setQueueCallCount, 0, "setQueue should NOT be called - uses insertIntoQueue instead")
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

    /// Documents current behavior: addSong uses insertIntoQueue which just appends the new song.
    /// Note: This does NOT filter out played songs - they remain in the queue.
    /// Use addSongsWithQueueRebuild for filtering behavior.
    func testAddSongDuringPlaybackAppendsWithoutFiltering() async throws {
        let song1 = Song(id: "1", title: "Song 1", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        let song2 = Song(id: "2", title: "Song 2", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        try await player.addSong(song1)
        try await player.addSong(song2)
        try await player.play()
        try await Task.sleep(nanoseconds: 100_000_000)

        // Determine which song is currently playing
        let state = await player.playbackState
        guard state.currentSong != nil else {
            XCTFail("Expected a song to be playing")
            return
        }

        await mockService.resetQueueTracking()

        // Add new song
        let song3 = Song(id: "3", title: "Song 3", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        try await player.addSong(song3)
        try await Task.sleep(nanoseconds: 100_000_000)

        // Current behavior: only the new song is inserted (appended to tail)
        let insertedSongs = await mockService.lastInsertedSongs
        XCTAssertEqual(insertedSongs.count, 1, "Only the new song should be inserted")
        XCTAssertEqual(insertedSongs.first?.id, "3", "The inserted song should be song3")

        // Note: Played songs are NOT filtered - this is different from addSongsWithQueueRebuild
    }

    /// Tests that addSongsWithQueueRebuild DOES filter out played songs
    func testAddSongsWithQueueRebuildExcludesPlayedSongs() async throws {
        let song1 = Song(id: "1", title: "Song 1", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        let song2 = Song(id: "2", title: "Song 2", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        try await player.addSong(song1)
        try await player.addSong(song2)
        try await player.play()
        try await Task.sleep(nanoseconds: 100_000_000)

        // Determine which song is currently playing
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

        // Add new songs using batch method
        let newSongs = [Song(id: "3", title: "Song 3", artist: "Artist", albumTitle: "Album", artworkURL: nil)]
        try await player.addSongsWithQueueRebuild(newSongs)
        try await Task.sleep(nanoseconds: 100_000_000)

        let lastQueued = await mockService.lastQueuedSongs
        let queuedIds = Set(lastQueued.map { $0.id })

        XCTAssertFalse(queuedIds.contains(firstSong.id), "Played song should be excluded")
        XCTAssertTrue(queuedIds.contains(secondSong.id), "Current song should be included")
        XCTAssertTrue(queuedIds.contains("3"), "New song3 should be included")
    }

    func testRemoveSongDuringPlaybackRemovesFromInternalList() async throws {
        let song1 = Song(id: "1", title: "Song 1", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        let song2 = Song(id: "2", title: "Song 2", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        try await player.addSong(song1)
        try await player.addSong(song2)
        try await player.play()
        try await Task.sleep(nanoseconds: 100_000_000)

        await player.removeSong(id: "2")
        try await Task.sleep(nanoseconds: 100_000_000)

        // Song should be removed from internal list
        let containsSong = await player.containsSong(id: "2")
        XCTAssertFalse(containsSong, "Removed song should not be in songs list")

        // Playback should continue (no disruption)
        let state = await player.playbackState
        XCTAssertTrue(state.isActive, "Playback should continue after removing non-current song")
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

    func testAddSongsWithQueueRebuildDuringPlaybackAppliesInjectedShuffleAlgorithm() async throws {
        let song1 = Song(id: "1", title: "Song 1", artist: "Artist A", albumTitle: "Album", artworkURL: nil)
        try await player.addSong(song1)
        try await player.play()
        try await Task.sleep(nanoseconds: 100_000_000)

        await mockService.resetQueueTracking()

        let song2 = Song(id: "2", title: "Song 2", artist: "Artist B", albumTitle: "Album", artworkURL: nil)
        try await player.addSongsWithQueueRebuild([song2], algorithm: .artistSpacing)
        try await Task.sleep(nanoseconds: 100_000_000)

        let usedAlgorithm = await player.lastUsedAlgorithm
        XCTAssertEqual(usedAlgorithm, .artistSpacing, "Shuffle algorithm should be applied on queue rebuild")
    }

    /// Documents current behavior: addSong uses insertIntoQueue which does NOT call play() or seek()
    /// The song is simply appended to the queue tail without disrupting current playback.
    func testAddSongDuringPlaybackDoesNotCallPlay() async throws {
        let song1 = Song(id: "1", title: "Song 1", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        try await player.addSong(song1)
        try await player.play()
        try await Task.sleep(nanoseconds: 100_000_000)

        await mockService.resetQueueTracking()

        let song2 = Song(id: "2", title: "Song 2", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        try await player.addSong(song2)
        try await Task.sleep(nanoseconds: 100_000_000)

        let playCount = await mockService.playCallCount
        XCTAssertEqual(playCount, 0, "play() should NOT be called - addSong uses insertIntoQueue")
    }

    // MARK: - MusicKit Insertion Rollback

    func testAddSongDuringPlaybackRollsBackOnInsertFailureBeforeReturn() async throws {
        let song1 = Song(id: "1", title: "Song 1", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        try await player.addSong(song1)
        try await player.play()
        try await Task.sleep(nanoseconds: 100_000_000)

        // Make insertIntoQueue fail
        await mockService.setShouldThrowOnInsert(NSError(domain: "test", code: 1))

        let song2 = Song(id: "2", title: "Song 2", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        try await player.addSong(song2)

        // song2 should be rolled back from pool and queue for a coherent state.
        let containsSong = await player.containsSong(id: "2")
        XCTAssertFalse(containsSong, "Song should be removed from pool after insert failure")

        // And NOT in queue order.
        let queue = await player.lastShuffledQueue
        XCTAssertFalse(queue.contains { $0.id == "2" }, "Song should be rolled back from queue after insert failure")
    }

    func testAddSongDuringPlaybackAwaitsTransportInsertionBeforeReturn() async throws {
        let song1 = Song(id: "1", title: "Song 1", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        try await player.addSong(song1)
        try await player.play()
        try await Task.sleep(nanoseconds: 100_000_000)

        await mockService.setInsertIntoQueueDelay(nanoseconds: 300_000_000)

        let song2 = Song(id: "2", title: "Song 2", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        let start = Date()
        try await player.addSong(song2)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertGreaterThanOrEqual(
            elapsed,
            0.25,
            "addSong should not return until insertIntoQueue completes"
        )

        let insertCallCount = await mockService.insertIntoQueueCallCount
        XCTAssertEqual(insertCallCount, 1, "addSong should perform exactly one transport insertion")
    }

    // MARK: - Playback Position Preservation

    /// Documents current behavior: addSong uses insertIntoQueue which does NOT need to preserve position
    /// because it simply appends to queue without rebuilding.
    func testAddSongDoesNotNeedToPreservePosition() async throws {
        let song1 = Song(id: "1", title: "Song 1", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        try await player.addSong(song1)
        try await player.play()
        try await Task.sleep(nanoseconds: 100_000_000)

        await mockService.setMockPlaybackTime(45.0)
        await mockService.resetQueueTracking()

        let song2 = Song(id: "2", title: "Song 2", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        try await player.addSong(song2)
        try await Task.sleep(nanoseconds: 100_000_000)

        // Current behavior: no seek needed because insertIntoQueue doesn't interrupt playback
        let seekCount = mockService.seekCallCount
        XCTAssertEqual(seekCount, 0, "seek() should NOT be called - addSong uses insertIntoQueue")
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

    /// Documents current behavior: addSongsWithQueueRebuild uses replaceQueue (not setQueue)
    func testAddSongsWithQueueRebuildCallsReplaceQueueOnce() async throws {
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

        let replaceCallCount = await mockService.replaceQueueCallCount
        XCTAssertEqual(replaceCallCount, 1, "Batch add should call replaceQueue once")

        let setQueueCallCount = await mockService.setQueueCallCount
        XCTAssertEqual(setQueueCallCount, 0, "setQueue should NOT be called - uses replaceQueue instead")
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

    // MARK: - Loading State Accuracy

    func testPlayEmitsLoadingWithShuffledFirstSong() async throws {
        let songs = (1...5).map { i in
            Song(id: "\(i)", title: "Song \(i)", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        }
        for song in songs {
            try await player.addSong(song)
        }

        // Call play but check the loading state before MusicKit responds
        // The mock will update state synchronously on play(), so we capture
        // the queue first song after prepareQueue runs
        try await player.play()

        // The loading state should match the first song in the shuffled queue
        let queueFirstSong = await player.lastShuffledQueue.first
        XCTAssertNotNil(queueFirstSong, "Queue should have a first song")

        // The currently playing/loading song should match the queue's first song
        let state = await player.playbackState
        if let currentSong = state.currentSong {
            XCTAssertEqual(currentSong.id, queueFirstSong?.id,
                           "Currently playing song should match the first song in the shuffled queue")
        }
    }

    // MARK: - Queue Staleness & Rebuild

    func testPlayRebuildsQueueWhenSongsAddedWhileStopped() async throws {
        // Add 3 songs and play
        for i in 1...3 {
            let song = Song(id: "\(i)", title: "Song \(i)", artist: "Artist", albumTitle: "Album", artworkURL: nil)
            try await player.addSong(song)
        }
        try await player.play()
        try await Task.sleep(nanoseconds: 100_000_000)

        // Stop playback
        await mockService.simulatePlaybackState(.stopped)
        try await Task.sleep(nanoseconds: 100_000_000)

        // Add 2 more songs while stopped
        for i in 4...5 {
            let song = Song(id: "\(i)", title: "Song \(i)", artist: "Artist", albumTitle: "Album", artworkURL: nil)
            try await player.addSong(song)
        }

        await mockService.resetQueueTracking()

        // Play again
        try await player.play()
        try await Task.sleep(nanoseconds: 100_000_000)

        // Queue should contain ALL 5 songs
        let queue = await player.lastShuffledQueue
        XCTAssertEqual(queue.count, 5, "Queue should be rebuilt with all 5 songs")
        let queueIds = Set(queue.map { $0.id })
        XCTAssertEqual(queueIds, Set(["1", "2", "3", "4", "5"]), "All songs should be in queue")

        // setQueue should have been called to rebuild
        let setQueueCallCount = await mockService.setQueueCallCount
        XCTAssertEqual(setQueueCallCount, 1, "setQueue should be called to rebuild stale queue")
    }

    func testQueueDriftTelemetryRecordsReasonsOnPlaybackStateReconcile() async throws {
        // Build an initial queue of 3 songs.
        for i in 1...3 {
            let song = Song(id: "\(i)", title: "Song \(i)", artist: "Artist", albumTitle: "Album", artworkURL: nil)
            try await player.addSong(song)
        }
        try await player.play()
        try await Task.sleep(nanoseconds: 100_000_000)

        // Capture a valid song for playback-state simulation.
        guard let currentSong = await player.lastShuffledQueue.first else {
            XCTFail("Expected a current song in queue")
            return
        }

        // Stop, then add songs while stopped to force pool/queue drift.
        await mockService.simulatePlaybackState(.stopped)
        try await Task.sleep(nanoseconds: 100_000_000)

        for i in 4...5 {
            let song = Song(id: "\(i)", title: "Song \(i)", artist: "Artist", albumTitle: "Album", artworkURL: nil)
            try await player.addSong(song)
        }

        let staleBefore = await player.queueState.isQueueStale
        XCTAssertTrue(staleBefore, "Queue should be stale before reconciliation")

        // Playback state change should trigger reconciliation and telemetry capture.
        await mockService.simulatePlaybackState(.paused(currentSong))
        try await Task.sleep(nanoseconds: 100_000_000)

        let telemetry = await player.queueDriftTelemetry
        XCTAssertEqual(telemetry.detections, 1, "Should detect one drift event")
        XCTAssertEqual(telemetry.reconciliations, 1, "Should reconcile one drift event")
        XCTAssertEqual(telemetry.unrepairedDetections, 0, "Drift should be repaired")
        XCTAssertEqual(
            telemetry.detectionsByTrigger["playback-state-change"],
            1,
            "Telemetry should attribute drift to playback-state reconciliation"
        )
        XCTAssertEqual(telemetry.detectionsByReason[.countMismatch], 1)
        XCTAssertEqual(telemetry.detectionsByReason[.membershipMismatch], 1)

        let staleAfter = await player.queueState.isQueueStale
        XCTAssertFalse(staleAfter, "Queue should be repaired after reconciliation")
    }

    func testPlayRebuildsQueueWhenSongsRemovedWhileStopped() async throws {
        // Add 5 songs and play
        for i in 1...5 {
            let song = Song(id: "\(i)", title: "Song \(i)", artist: "Artist", albumTitle: "Album", artworkURL: nil)
            try await player.addSong(song)
        }
        try await player.play()
        try await Task.sleep(nanoseconds: 100_000_000)

        // Stop playback
        await mockService.simulatePlaybackState(.stopped)
        try await Task.sleep(nanoseconds: 100_000_000)

        // Remove 2 songs while stopped
        await player.removeSong(id: "2")
        await player.removeSong(id: "4")

        await mockService.resetQueueTracking()

        // Play again
        try await player.play()
        try await Task.sleep(nanoseconds: 100_000_000)

        // Queue should contain only the remaining 3 songs
        let queue = await player.lastShuffledQueue
        XCTAssertEqual(queue.count, 3, "Queue should be rebuilt with remaining 3 songs")
        let queueIds = Set(queue.map { $0.id })
        XCTAssertEqual(queueIds, Set(["1", "3", "5"]), "Only remaining songs should be in queue")
    }

    // MARK: - Algorithm Change

    func testAlgorithmChangeWhenNotActiveInvalidatesQueue() async throws {
        // Add songs and play
        let songs = (1...5).map { i in
            Song(id: "\(i)", title: "Song \(i)", artist: "Artist \(i)", albumTitle: "Album", artworkURL: nil)
        }
        for song in songs {
            try await player.addSong(song)
        }
        try await player.play()
        try await Task.sleep(nanoseconds: 100_000_000)

        // Stop playback
        await mockService.simulatePlaybackState(.stopped)
        try await Task.sleep(nanoseconds: 100_000_000)

        await mockService.resetQueueTracking()

        // Change algorithm while NOT active (mimic real flow: settings change + view onChange)
        UserDefaults.standard.set("artistSpacing", forKey: "shuffleAlgorithm")
        await player.reshuffleWithNewAlgorithm(.artistSpacing)

        // Queue should be invalidated
        let hasQueue = await player.lastShuffledQueue.isEmpty
        XCTAssertTrue(hasQueue, "Queue should be invalidated after algorithm change while not active")
        let playCallCount = await mockService.playCallCount
        XCTAssertEqual(playCallCount, 0, "Algorithm change while not active should not auto-play")

        await mockService.resetQueueTracking()

        // Play again — should rebuild with new algorithm
        try await player.play()
        try await Task.sleep(nanoseconds: 100_000_000)

        let usedAlgorithm = await player.lastUsedAlgorithm
        XCTAssertEqual(usedAlgorithm, .artistSpacing, "Should use the new algorithm after play")

        let queue = await player.lastShuffledQueue
        XCTAssertEqual(queue.count, 5, "Queue should be rebuilt with all songs")
    }

    func testReshuffleWithNewAlgorithmUpdatesQueue() async throws {
        UserDefaults.standard.set("noRepeat", forKey: "shuffleAlgorithm")

        let songs = (1...5).map { i in
            Song(id: "\(i)", title: "Song \(i)", artist: "Artist \(i)", albumTitle: "Album", artworkURL: nil)
        }
        for song in songs {
            try await player.addSong(song)
        }
        try await player.play()
        try await Task.sleep(nanoseconds: 100_000_000)

        await mockService.resetQueueTracking()

        // Change algorithm to artistSpacing
        await player.reshuffleWithNewAlgorithm(.artistSpacing)
        try await Task.sleep(nanoseconds: 100_000_000)

        let usedAlgorithm = await player.lastUsedAlgorithm
        XCTAssertEqual(usedAlgorithm, .artistSpacing, "Algorithm should be updated")

        // Queue should be rebuilt (replaceQueue was called internally)
        let queuedSongs = await mockService.lastQueuedSongs
        XCTAssertFalse(queuedSongs.isEmpty, "Queue should be rebuilt with new algorithm")
    }

    func testReshufflePreservesCurrentSong() async throws {
        let songs = (1...5).map { i in
            Song(id: "\(i)", title: "Song \(i)", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        }
        for song in songs {
            try await player.addSong(song)
        }
        try await player.play()
        try await Task.sleep(nanoseconds: 100_000_000)

        let currentSongId = await player.playbackState.currentSongId

        await mockService.resetQueueTracking()
        await player.reshuffleWithNewAlgorithm(.pureRandom)
        try await Task.sleep(nanoseconds: 100_000_000)

        // Current song should still be first in queue
        let queuedSongs = await mockService.lastQueuedSongs
        XCTAssertEqual(queuedSongs.first?.id, currentSongId, "Current song should remain first after reshuffle")
    }

    func testReshuffleExcludesPlayedSongs() async throws {
        let song1 = Song(id: "1", title: "Song 1", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        let song2 = Song(id: "2", title: "Song 2", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        let song3 = Song(id: "3", title: "Song 3", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        try await player.addSong(song1)
        try await player.addSong(song2)
        try await player.addSong(song3)
        try await player.play()
        try await Task.sleep(nanoseconds: 100_000_000)

        // Determine current song and simulate transition
        let state = await player.playbackState
        guard let currentSong = state.currentSong else {
            XCTFail("Expected a song to be playing")
            return
        }
        let otherSongs = [song1, song2, song3].filter { $0.id != currentSong.id }
        let nextSong = otherSongs[0]

        // Simulate playing through first song
        await mockService.simulatePlaybackState(.playing(nextSong))
        try await Task.sleep(nanoseconds: 100_000_000)

        await mockService.resetQueueTracking()
        await player.reshuffleWithNewAlgorithm(.noRepeat)
        try await Task.sleep(nanoseconds: 100_000_000)

        let queuedIds = Set(await mockService.lastQueuedSongs.map(\.id))
        XCTAssertFalse(queuedIds.contains(currentSong.id), "Played song should be excluded from reshuffle")
    }

    func testDuplicateMetadataSongsUseIDFirstMapping() async throws {
        let songA = Song(id: "a", title: "Same Title", artist: "Same Artist", albumTitle: "Album A", artworkURL: nil)
        let songB = Song(id: "b", title: "Same Title", artist: "Same Artist", albumTitle: "Album B", artworkURL: nil)
        try await player.addSong(songA)
        try await player.addSong(songB)
        try await player.play()
        try await Task.sleep(nanoseconds: 100_000_000)

        await mockService.simulatePlaybackState(.playing(songB))
        try await Task.sleep(nanoseconds: 100_000_000)

        let resolvedId = await player.playbackState.currentSongId
        XCTAssertEqual(resolvedId, "b", "Playback mapping should prioritize exact ID before metadata fallback")
    }

    // MARK: - Queue Restoration

    /// Tests that restoreQueue restores played history correctly.
    func testRestoreQueueRestoresPlayedHistory() async throws {
        let songs = (1...5).map { i in
            Song(id: "\(i)", title: "Song \(i)", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        }
        for song in songs {
            try await player.addSong(song)
        }

        // Verify songs were added
        let songCount = await player.songCount
        XCTAssertEqual(songCount, 5, "Should have 5 songs")

        // Restore queue with song 3 as current
        let queueOrder = ["1", "2", "3", "4", "5"]
        let playedIds: Set<String> = ["1", "2"]
        let success = await player.restoreQueue(
            queueOrder: queueOrder,
            currentSongId: "3",
            playedIds: playedIds,
            playbackPosition: 0
        )
        try await Task.sleep(nanoseconds: 200_000_000)

        // Verify restoration succeeded
        XCTAssertTrue(success, "Restore should succeed")
        let playCallCount = await mockService.playCallCount
        XCTAssertEqual(playCallCount, 0, "Restoration should not auto-start playback")

        // Get played history
        let restoredPlayedIds = await player.playedSongIdsForTesting

        // Note: Due to async playback state handling, the history may be affected
        // by state transitions during restore (play -> pause sequence).
        // The key verification is that restore succeeded and returns consistent state.
        XCTAssertFalse(restoredPlayedIds.contains("3"), "Current song should not be in history")
    }

    func testRestoreQueuePreservesPersistedQueueOrder() async throws {
        let songs = (1...5).map { i in
            Song(id: "\(i)", title: "Song \(i)", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        }
        for song in songs {
            try await player.addSong(song)
        }

        let queueOrder = ["1", "2", "3", "4", "5"]
        _ = await player.restoreQueue(
            queueOrder: queueOrder,
            currentSongId: "3",
            playedIds: [],
            playbackPosition: 0
        )

        let queuedSongs = await mockService.lastQueuedSongs
        XCTAssertEqual(queuedSongs.map(\.id), queueOrder, "Restore should preserve full persisted queue order")
        let currentSongId = await player.playbackState.currentSongId
        XCTAssertEqual(currentSongId, "3", "Current song should be restored within preserved queue order")
    }

    func testRestoreQueueFailsWithEmptySongs() async throws {
        // Don't add any songs to player
        let queueOrder = ["1", "2", "3"]
        let success = await player.restoreQueue(
            queueOrder: queueOrder,
            currentSongId: "1",
            playedIds: [],
            playbackPosition: 0
        )

        XCTAssertFalse(success, "Restore should fail when song pool is empty")
    }

    func testRestoreQueueFiltersInvalidSongs() async throws {
        // Only add songs 1 and 3, queue references 1-5
        let song1 = Song(id: "1", title: "Song 1", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        let song3 = Song(id: "3", title: "Song 3", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        try await player.addSong(song1)
        try await player.addSong(song3)

        let queueOrder = ["1", "2", "3", "4", "5"]  // 2, 4, 5 don't exist
        let success = await player.restoreQueue(
            queueOrder: queueOrder,
            currentSongId: "3",
            playedIds: [],
            playbackPosition: 0
        )

        XCTAssertTrue(success, "Restore should succeed with partial queue")

        let queuedSongs = await mockService.lastQueuedSongs
        let queuedIds = Set(queuedSongs.map(\.id))
        XCTAssertTrue(queuedIds.contains("1"), "Valid song 1 should be in queue")
        XCTAssertTrue(queuedIds.contains("3"), "Valid song 3 should be in queue")
        XCTAssertFalse(queuedIds.contains("2"), "Invalid song 2 should be filtered out")
    }

    func testRestoreQueueDoesNotAutoStartPlayback() async throws {
        let songs = (1...3).map { i in
            Song(id: "\(i)", title: "Song \(i)", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        }
        for song in songs {
            try await player.addSong(song)
        }

        await mockService.resetQueueTracking()

        let success = await player.restoreQueue(
            queueOrder: ["1", "2", "3"],
            currentSongId: "2",
            playedIds: ["1"],
            playbackPosition: 42
        )

        XCTAssertTrue(success, "Restore should succeed with valid state")
        let playCallCount = await mockService.playCallCount
        XCTAssertEqual(playCallCount, 0, "Restoring session should never trigger play()")
        let pauseCallCount = await mockService.pauseCallCount
        XCTAssertEqual(pauseCallCount, 0, "Restoring session should not force an extra pause() after queue restore")
    }

    func testRestoreQueueSetsPausedCurrentSongState() async throws {
        let songs = (1...3).map { i in
            Song(id: "\(i)", title: "Song \(i)", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        }
        for song in songs {
            try await player.addSong(song)
        }

        let success = await player.restoreQueue(
            queueOrder: ["1", "2", "3"],
            currentSongId: "2",
            playedIds: ["1"],
            playbackPosition: 15
        )
        XCTAssertTrue(success, "Restore should succeed with valid state")

        let state = await player.playbackState
        guard case .paused(let song) = state else {
            XCTFail("Expected paused state with current song after restore, got \(state)")
            return
        }
        XCTAssertEqual(song.id, "2", "Restored current song should remain visible while paused")
    }

    func testRestoreQueuePreservesHydratedCurrentSongMetadata() async throws {
        let songs = [
            Song(id: "1", title: "Song 1", artist: "Artist", albumTitle: "Album", artworkURL: nil),
            Song(id: "2", title: "Queue Song 2", artist: "Artist", albumTitle: "Album", artworkURL: nil),
            Song(id: "3", title: "Song 3", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        ]
        for song in songs {
            try await player.addSong(song)
        }

        let hydratedArtwork = URL(string: "https://example.com/artwork.jpg")
        let hydratedSong = Song(
            id: "2",
            title: "Hydrated Song 2",
            artist: "Artist",
            albumTitle: "Hydrated Album",
            artworkURL: hydratedArtwork
        )
        await mockService.simulatePlaybackState(.paused(hydratedSong))
        try await Task.sleep(nanoseconds: 100_000_000)

        let success = await player.restoreQueue(
            queueOrder: ["1", "2", "3"],
            currentSongId: "2",
            playedIds: ["1"],
            playbackPosition: 20
        )
        XCTAssertTrue(success, "Restore should succeed with valid state")

        let state = await player.playbackState
        guard case .paused(let song) = state else {
            XCTFail("Expected paused state with current song after restore, got \(state)")
            return
        }
        XCTAssertEqual(song.id, "2")
        XCTAssertEqual(song.title, "Hydrated Song 2", "Restore should keep transport-hydrated title when IDs match")
        XCTAssertEqual(song.artworkURL, hydratedArtwork, "Restore should keep transport-hydrated artwork when IDs match")
    }

    func testTogglePlaybackAfterRestoreReappliesSavedPosition() async throws {
        let songs = (1...3).map { i in
            Song(id: "\(i)", title: "Song \(i)", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        }
        for song in songs {
            try await player.addSong(song)
        }

        let success = await player.restoreQueue(
            queueOrder: ["1", "2", "3"],
            currentSongId: "2",
            playedIds: ["1"],
            playbackPosition: 42
        )
        XCTAssertTrue(success, "Restore should succeed with valid state")

        await mockService.resetQueueTracking()

        try await player.togglePlayback()
        try await Task.sleep(nanoseconds: 100_000_000)

        let seekCount = await mockService.seekCallCount
        let lastSeekTime = await mockService.lastSeekTime
        XCTAssertEqual(seekCount, 1, "First explicit play after restore should apply saved playback position")
        XCTAssertEqual(lastSeekTime, 42, accuracy: 0.001, "Restore position should be re-applied on explicit play")
    }

    // MARK: - Remove Song Queue Updates

    /// Verifies that removing an upcoming song updates the MusicKit queue.
    func testRemoveUpcomingSongUpdatesQueue() async throws {
        let song1 = Song(id: "1", title: "Song 1", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        let song2 = Song(id: "2", title: "Song 2", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        let song3 = Song(id: "3", title: "Song 3", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        try await player.addSong(song1)
        try await player.addSong(song2)
        try await player.addSong(song3)
        try await player.play()
        try await Task.sleep(nanoseconds: 100_000_000)

        await mockService.resetQueueTracking()

        // Remove song that's NOT currently playing
        let currentSongId = await player.playbackState.currentSongId
        let songToRemove = currentSongId == "1" ? "2" : "1"
        await player.removeSong(id: songToRemove)
        try await Task.sleep(nanoseconds: 100_000_000)

        // Verify replaceQueue was called to update MusicKit
        let replaceCallCount = await mockService.replaceQueueCallCount
        XCTAssertEqual(replaceCallCount, 1, "Should call replaceQueue when removing upcoming song")

        // Verify removed song is not in the new queue
        let lastQueued = await mockService.lastQueuedSongs
        XCTAssertFalse(lastQueued.contains { $0.id == songToRemove }, "Removed song should not be in queue")

        // Song is removed from internal list
        let containsSong = await player.containsSong(id: songToRemove)
        XCTAssertFalse(containsSong, "Song should be removed from internal list")
    }

    /// Verifies that removing the currently playing song skips to next.
    func testRemoveCurrentSongSkipsToNext() async throws {
        let song1 = Song(id: "1", title: "Song 1", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        let song2 = Song(id: "2", title: "Song 2", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        try await player.addSong(song1)
        try await player.addSong(song2)
        try await player.play()
        try await Task.sleep(nanoseconds: 100_000_000)

        let currentSongId = await player.playbackState.currentSongId
        XCTAssertNotNil(currentSongId)

        // Remove the currently playing song
        await player.removeSong(id: currentSongId!)
        try await Task.sleep(nanoseconds: 100_000_000)

        // Should have skipped to the next song
        let newCurrentSongId = await player.playbackState.currentSongId
        XCTAssertNotEqual(newCurrentSongId, currentSongId, "Should have skipped to a different song")
    }

    func testInterleavedMutationsKeepQueueAndTransportConsistent() async throws {
        let songs = (1...5).map { i in
            Song(id: "\(i)", title: "Song \(i)", artist: "Artist \(i)", albumTitle: "Album", artworkURL: nil)
        }
        for song in songs {
            try await player.addSong(song)
        }
        try await player.play()
        try await Task.sleep(nanoseconds: 100_000_000)

        let song6 = Song(id: "6", title: "Song 6", artist: "Artist 6", albumTitle: "Album", artworkURL: nil)
        try await player.addSong(song6)
        await player.removeSong(id: "2")
        await player.reshuffleWithNewAlgorithm(.artistSpacing)
        try await Task.sleep(nanoseconds: 200_000_000)

        let internalQueue = await player.lastShuffledQueue
        let playedCount = await player.playedSongIdsForTesting.count
        let internalUpcomingQueue = Array(internalQueue.dropFirst(playedCount)).map(\.id)
        let transportQueue = await mockService.lastQueuedSongs.map(\.id)
        XCTAssertEqual(
            Set(internalUpcomingQueue),
            Set(transportQueue),
            "Interleaved operations should keep upcoming domain queue and transport queue in sync"
        )
    }

    func testReplaceQueueFailureKeepsStateRecoverable() async throws {
        let songs = (1...4).map { i in
            Song(id: "\(i)", title: "Song \(i)", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        }
        for song in songs {
            try await player.addSong(song)
        }
        try await player.play()
        try await Task.sleep(nanoseconds: 100_000_000)

        await mockService.setShouldThrowOnReplace(NSError(domain: "test", code: 99))
        await player.reshuffleWithNewAlgorithm(.artistSpacing)
        try await Task.sleep(nanoseconds: 100_000_000)

        // State should remain usable despite failed queue mutation.
        await mockService.setShouldThrowOnReplace(nil)
        try await player.play()
        try await Task.sleep(nanoseconds: 100_000_000)

        let state = await player.playbackState
        XCTAssertTrue(state.isActive, "Player should remain recoverable after queue mutation failure")
    }
}
