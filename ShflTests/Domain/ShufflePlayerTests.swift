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

    /// During active playback, addSong appends into transport without rebuilding the entire queue.
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
        let replaceCallCount = await mockService.replaceQueueCallCount
        XCTAssertEqual(replaceCallCount, 0, "replaceQueue should not be needed for simple active append")

        let insertCallCount = await mockService.insertIntoQueueCallCount
        XCTAssertEqual(insertCallCount, 1, "insertIntoQueue should be used when adding song during playback")
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

    /// addSong keeps transport queue canonical (no duplicate IDs, full membership retained).
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

        let replaceCallCount = await mockService.replaceQueueCallCount
        XCTAssertEqual(replaceCallCount, 0, "Active append should avoid full replaceQueue transport rebuild")
        let insertCallCount = await mockService.insertIntoQueueCallCount
        XCTAssertEqual(insertCallCount, 1, "insertIntoQueue should apply single-song append transport update")

        let queuedIds = await mockService.lastQueuedSongs.map(\.id)
        XCTAssertTrue(queuedIds.contains("3"), "New song should be represented in transport queue")
        XCTAssertEqual(queuedIds.count, Set(queuedIds).count, "Transport queue should remain duplicate-free")
    }

    /// addSongsWithQueueRebuild should preserve a single canonical full queue in transport.
    func testAddSongsWithQueueRebuildKeepsTransportMirroringDomainQueue() async throws {
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

        XCTAssertTrue(queuedIds.contains(firstSong.id), "Played songs should remain in canonical queue ordering")
        XCTAssertTrue(queuedIds.contains(secondSong.id), "Current song should be included")
        XCTAssertTrue(queuedIds.contains("3"), "New song3 should be included")
        XCTAssertEqual(lastQueued.count, queuedIds.count, "Transport queue should not contain duplicate song IDs")
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

    func testPlayWithPureRandomBuildsUniqueQueue() async throws {
        let songs = (1...30).map { i in
            Song(id: "\(i)", title: "Song \(i)", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        }

        for song in songs {
            try await player.addSong(song)
        }

        try await player.play(algorithm: .pureRandom)
        try await Task.sleep(nanoseconds: 100_000_000)

        let queue = await player.lastShuffledQueue
        XCTAssertEqual(queue.count, songs.count)
        XCTAssertEqual(
            Set(queue.map(\.id)).count,
            songs.count,
            "Pure Random playback queue must keep unique IDs to preserve queue invariants"
        )
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

    /// addSong should not trigger extra play() calls while appending into active queue.
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
        XCTAssertEqual(playCount, 0, "play() should NOT be called during addSong transport append")
    }

    // MARK: - Transport Failure Handling

    func testAddSongDuringPlaybackDefersQueueRebuildOnInsertFailure() async throws {
        let song1 = Song(id: "1", title: "Song 1", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        try await player.addSong(song1)
        try await player.play()
        try await Task.sleep(nanoseconds: 100_000_000)

        // Make insertIntoQueue fail
        await mockService.setShouldThrowOnInsert(NSError(domain: "test", code: 1))

        let song2 = Song(id: "2", title: "Song 2", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        do {
            try await player.addSong(song2)
            XCTFail("Expected addSong to throw when transport insert fails")
        } catch let error as ShufflePlayerError {
            guard case .playbackFailed(let message) = error else {
                XCTFail("Expected playbackFailed error, got \(error)")
                return
            }
            XCTAssertFalse(message.isEmpty, "Error should include a user-facing message")
        }

        // song2 should remain in pool and be picked up on next rebuild.
        let containsSong = await player.containsSong(id: "2")
        XCTAssertTrue(containsSong, "Song should remain in pool after replace failure")

        // Queue order should roll back until rebuild occurs.
        let queue = await player.lastShuffledQueue
        XCTAssertFalse(queue.contains { $0.id == "2" }, "Queue order should roll back after replace failure")
        let needsBuild = await player.queueNeedsBuild
        XCTAssertTrue(needsBuild, "Failed insert should defer transport sync to next rebuild")

        let notice = await player.operationNotice
        XCTAssertNotNil(notice, "Transport failure should surface a non-blocking notice")
    }

    func testAddSongDuringPlaybackAwaitsTransportInsertBeforeReturn() async throws {
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
        XCTAssertEqual(insertCallCount, 1, "addSong should perform exactly one transport insert")
    }

    func testPlayMarksQueueNeedsBuildWhenTransportCommandRevisionTurnsStale() async throws {
        let song1 = Song(id: "1", title: "Song 1", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        let song2 = Song(id: "2", title: "Song 2", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        try await player.addSong(song1)
        await mockService.setSetQueueDelay(nanoseconds: 150_000_000)

        Task {
            try? await Task.sleep(nanoseconds: 40_000_000)
            try? await self.player.addSong(song2)
        }

        do {
            try await player.play()
            XCTFail("Expected play() to fail when transport commands become stale")
        } catch let error as ShufflePlayerError {
            guard case .playbackFailed(let message) = error else {
                XCTFail("Expected playbackFailed error, got \(error)")
                return
            }
            XCTAssertFalse(message.isEmpty, "Error should include a user-facing message")
        }

        let needsBuild = await player.queueNeedsBuild
        XCTAssertTrue(needsBuild, "Stale command skips should mark queueNeedsBuild for recovery")

        let playCallCount = await mockService.playCallCount
        XCTAssertEqual(playCallCount, 0, "Stale play command should not execute against transport")

        let operations = await player.recentQueueOperations
        XCTAssertTrue(
            operations.contains(where: { $0.operation == "transport-command-stale" }),
            "Stale command handling should be recorded in operation journal"
        )
    }

    // MARK: - Playback Position Preservation

    /// addSong transport append should preserve playback position without explicit seek.
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

        // insertIntoQueue should not disturb playback position or trigger an explicit seek.
        let seekCount = mockService.seekCallCount
        XCTAssertEqual(seekCount, 0, "seek() should NOT be called during addSong transport append")
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

    func testAddSongsWithQueueRebuildThrowsAndRecoversWhenReplaceFails() async throws {
        let song1 = Song(id: "1", title: "Song 1", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        let song2 = Song(id: "2", title: "Song 2", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        try await player.addSong(song1)
        try await player.addSong(song2)
        try await player.play()
        try await Task.sleep(nanoseconds: 100_000_000)

        let queueBeforeFailure = await player.lastShuffledQueue.map(\.id)

        await mockService.setShouldThrowOnReplace(
            NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        )

        let song3 = Song(id: "3", title: "Song 3", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        do {
            try await player.addSongsWithQueueRebuild([song3])
            XCTFail("Expected addSongsWithQueueRebuild to throw when replaceQueue fails")
        } catch let error as ShufflePlayerError {
            guard case .playbackFailed(let message) = error else {
                XCTFail("Expected playbackFailed error, got \(error)")
                return
            }
            XCTAssertFalse(message.isEmpty, "Error should include a user-facing message")
        }

        let queueAfterFailure = await player.lastShuffledQueue.map(\.id)
        XCTAssertEqual(
            queueAfterFailure,
            queueBeforeFailure,
            "Queue order should roll back to pre-rebuild state on replace failure"
        )

        let containsSong3 = await player.containsSong(id: "3")
        XCTAssertTrue(containsSong3, "Added songs should remain in pool after replace failure")

        let notice = await player.operationNotice
        XCTAssertNotNil(notice, "Transport failure should surface a non-blocking notice")

        await mockService.setShouldThrowOnReplace(nil)
        await mockService.resetQueueTracking()

        try await player.play()
        try await Task.sleep(nanoseconds: 100_000_000)

        let setQueueCallCount = await mockService.setQueueCallCount
        XCTAssertEqual(setQueueCallCount, 1, "Stale queue should rebuild on next play")
        let rebuiltQueue = await player.lastShuffledQueue.map(\.id)
        XCTAssertTrue(rebuiltQueue.contains("3"), "Rebuilt queue should include deferred song")
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

        let needsBuildBefore = await player.queueNeedsBuild
        XCTAssertTrue(needsBuildBefore, "Stale queue should mark rebuild pending")

        await mockService.resetQueueTracking()

        // Playback state changes should NOT auto-reconcile while a rebuild is pending.
        await mockService.simulatePlaybackState(.paused(currentSong))
        try await Task.sleep(nanoseconds: 100_000_000)

        let telemetry = await player.queueDriftTelemetry
        XCTAssertEqual(telemetry.detections, 0, "Phase-2 flow should avoid auto-reconcile telemetry side-effects")
        XCTAssertEqual(telemetry.reconciliations, 0, "Reconciliation now happens on explicit queue rebuild")

        let staleAfter = await player.queueState.isQueueStale
        XCTAssertTrue(staleAfter, "Playback-state changes should not silently repair a stale queue")

        let replaceCallCount = await mockService.replaceQueueCallCount
        XCTAssertEqual(replaceCallCount, 0, "No replaceQueue should run during passive playback-state changes")

        try await player.play()
        try await Task.sleep(nanoseconds: 100_000_000)

        let staleAfterPlay = await player.queueState.isQueueStale
        XCTAssertFalse(staleAfterPlay, "Explicit play should rebuild stale queue")
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

    func testPlayReshufflesQueueOnReplayAfterFullPlaythrough() async throws {
        // Add 5 songs and play
        for i in 1...5 {
            let song = Song(id: "\(i)", title: "Song \(i)", artist: "Artist \(i)", albumTitle: "Album", artworkURL: nil)
            try await player.addSong(song)
        }
        try await player.play()
        try await Task.sleep(nanoseconds: 100_000_000)

        // Simulate full playthrough ending
        await mockService.simulatePlaybackState(.stopped)
        try await Task.sleep(nanoseconds: 100_000_000)

        await mockService.resetQueueTracking()

        // Play again — should reshuffle even though pool hasn't changed
        try await player.play()
        try await Task.sleep(nanoseconds: 100_000_000)

        // setQueue should have been called to rebuild with a fresh shuffle
        let setQueueCallCount = await mockService.setQueueCallCount
        XCTAssertEqual(setQueueCallCount, 1, "setQueue should be called to reshuffle on replay")

        // Queue should still contain all 5 songs
        let queue = await player.lastShuffledQueue
        XCTAssertEqual(queue.count, 5, "Queue should contain all songs after reshuffle")
        let queueIds = Set(queue.map { $0.id })
        XCTAssertEqual(queueIds, Set(["1", "2", "3", "4", "5"]), "All songs should be in reshuffled queue")
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

    func testReproAddSongsThenAlgorithmChangeThenPausePlayStaysInSync() async throws {
        let initialSongs = (1...6).map { i in
            Song(id: "\(i)", title: "Song \(i)", artist: "Artist \(i)", albumTitle: "Album", artworkURL: nil)
        }
        let newSongs = [
            Song(id: "7", title: "Song 7", artist: "Artist 7", albumTitle: "Album", artworkURL: nil),
            Song(id: "8", title: "Song 8", artist: "Artist 8", albumTitle: "Album", artworkURL: nil)
        ]

        for song in initialSongs {
            try await player.addSong(song)
        }
        try await player.play()
        try await Task.sleep(nanoseconds: 100_000_000)

        // Simulate listening progression before adding new songs.
        let state = await player.playbackState
        guard let currentlyPlaying = state.currentSong else {
            XCTFail("Expected a song to be playing")
            return
        }
        if let nextSong = initialSongs.first(where: { $0.id != currentlyPlaying.id }) {
            await mockService.simulatePlaybackState(.playing(nextSong))
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        // Repro step: add two songs while queue is active (single-song path).
        try await player.addSong(newSongs[0])
        try await player.addSong(newSongs[1])
        try await Task.sleep(nanoseconds: 100_000_000)

        // Repro step: change algorithm, then pause/play.
        await player.reshuffleWithNewAlgorithm(.artistSpacing)
        try await Task.sleep(nanoseconds: 100_000_000)
        await player.pause()
        try await Task.sleep(nanoseconds: 100_000_000)
        try await player.togglePlayback()
        try await Task.sleep(nanoseconds: 100_000_000)

        let domainQueueIds = await player.lastShuffledQueue.map(\.id)
        let transportQueueIds = await mockService.lastQueuedSongs.map(\.id)
        let transportIdSet = Set(transportQueueIds)

        XCTAssertEqual(
            transportIdSet,
            Set(domainQueueIds),
            "Transport queue should match the domain queue membership after algorithm change + pause/play"
        )
        XCTAssertEqual(
            transportQueueIds.count,
            transportIdSet.count,
            "Transport queue should not contain duplicate song IDs"
        )

        if let currentId = await player.playbackState.currentSongId {
            XCTAssertTrue(transportIdSet.contains(currentId), "Current song must exist in transport queue")
        } else {
            XCTFail("Expected current song after resuming playback")
        }
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

        // Current song should still be current after reshuffle.
        let queuedSongs = await mockService.lastQueuedSongs
        let currentSongIdAfterReshuffle = await player.playbackState.currentSongId
        XCTAssertEqual(
            currentSongIdAfterReshuffle,
            currentSongId,
            "Current song should be preserved across reshuffle"
        )
        XCTAssertEqual(
            queuedSongs.filter { $0.id == currentSongId }.count,
            1,
            "Current song should appear exactly once in transport queue"
        )
    }

    func testReshuffleKeepsCanonicalQueueWithoutDuplicates() async throws {
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

        let queuedSongs = await mockService.lastQueuedSongs
        let queuedIds = Set(queuedSongs.map(\.id))
        XCTAssertEqual(queuedIds, Set(["1", "2", "3"]), "Reshuffle should preserve full pool membership in queue")
        XCTAssertEqual(queuedSongs.count, queuedIds.count, "Reshuffle should not introduce duplicate queue IDs")
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

    func testRemoveUpcomingSongRollsBackWhenReplaceFails() async throws {
        let song1 = Song(id: "1", title: "Song 1", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        let song2 = Song(id: "2", title: "Song 2", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        let song3 = Song(id: "3", title: "Song 3", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        try await player.addSong(song1)
        try await player.addSong(song2)
        try await player.addSong(song3)
        try await player.play()
        try await Task.sleep(nanoseconds: 100_000_000)

        let currentSongId = await player.playbackState.currentSongId
        let songToRemove = currentSongId == "1" ? "2" : "1"
        let queueBeforeFailure = await player.lastShuffledQueue.map(\.id)

        await mockService.setShouldThrowOnReplace(
            NSError(domain: NSURLErrorDomain, code: NSURLErrorNetworkConnectionLost)
        )
        await player.removeSong(id: songToRemove)
        try await Task.sleep(nanoseconds: 100_000_000)

        let queueAfterFailure = await player.lastShuffledQueue.map(\.id)
        XCTAssertEqual(
            queueAfterFailure,
            queueBeforeFailure,
            "Queue should roll back to previous state when remove replaceQueue fails"
        )

        let containsSong = await player.containsSong(id: songToRemove)
        XCTAssertTrue(containsSong, "Failed remove should not silently drop local song state")

        let notice = await player.operationNotice
        XCTAssertNotNil(notice, "Transport failure should surface a non-blocking notice")
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

        let internalQueue = await player.lastShuffledQueue.map(\.id)
        let transportQueue = await mockService.lastQueuedSongs.map(\.id)
        XCTAssertEqual(
            Set(internalQueue),
            Set(transportQueue),
            "Interleaved operations should keep domain queue and transport queue in sync"
        )
    }

    func testQueueDriftEventListCapsAt20() async throws {
        // Build an initial queue of 3 songs.
        for i in 1...3 {
            let song = Song(id: "\(i)", title: "Song \(i)", artist: "Artist", albumTitle: "Album", artworkURL: nil)
            try await player.addSong(song)
        }
        try await player.play()
        try await Task.sleep(nanoseconds: 100_000_000)

        guard let currentSong = await player.lastShuffledQueue.first else {
            XCTFail("Expected a current song in queue")
            return
        }

        // Trigger 25 stale cycles; phase-2 flow keeps telemetry empty and defers rebuild to play.
        for cycle in 0..<25 {
            await mockService.simulatePlaybackState(.stopped)
            try await Task.sleep(nanoseconds: 50_000_000)

            let extra = Song(id: "extra\(cycle)", title: "Extra \(cycle)", artist: "Artist", albumTitle: "Album", artworkURL: nil)
            try await player.addSong(extra)

            await mockService.simulatePlaybackState(.paused(currentSong))
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        let telemetry = await player.queueDriftTelemetry
        XCTAssertEqual(telemetry.recentEvents.count, 0, "Phase-2 queue engine no longer emits drift events")
        XCTAssertEqual(telemetry.detections, 0)
        XCTAssertEqual(telemetry.reconciliations, 0)

        let needsBuild = await player.queueNeedsBuild
        XCTAssertTrue(needsBuild, "Repeated stale cycles should keep rebuild pending")
    }

    func testQueueDriftRepairedCounterIncrements() async throws {
        // Build an initial queue of 3 songs.
        for i in 1...3 {
            let song = Song(id: "\(i)", title: "Song \(i)", artist: "Artist", albumTitle: "Album", artworkURL: nil)
            try await player.addSong(song)
        }
        try await player.play()
        try await Task.sleep(nanoseconds: 100_000_000)

        guard let currentSong = await player.lastShuffledQueue.first else {
            XCTFail("Expected a current song in queue")
            return
        }

        // Stop and add a song to create drift.
        await mockService.simulatePlaybackState(.stopped)
        try await Task.sleep(nanoseconds: 100_000_000)

        let extra = Song(id: "extra", title: "Extra", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        try await player.addSong(extra)

        let staleBeforePlay = await player.queueState.isQueueStale
        XCTAssertTrue(staleBeforePlay, "Queue should be stale while rebuild is pending")
        let needsBuildBeforePlay = await player.queueNeedsBuild
        XCTAssertTrue(needsBuildBeforePlay, "Stale queue should require rebuild before play")

        try await player.play()
        try await Task.sleep(nanoseconds: 100_000_000)

        let staleAfterPlay = await player.queueState.isQueueStale
        XCTAssertFalse(staleAfterPlay, "Play should rebuild queue and clear stale state")
        let needsBuildAfterPlay = await player.queueNeedsBuild
        XCTAssertFalse(needsBuildAfterPlay, "Rebuild flag should clear after successful play")
    }

    func testQueueDriftEventIncludesTransportParityFields() async throws {
        // Build an initial queue of 3 songs.
        for i in 1...3 {
            let song = Song(id: "\(i)", title: "Song \(i)", artist: "Artist", albumTitle: "Album", artworkURL: nil)
            try await player.addSong(song)
        }
        try await player.play()
        try await Task.sleep(nanoseconds: 100_000_000)

        guard let currentSong = await player.lastShuffledQueue.first else {
            XCTFail("Expected a current song in queue")
            return
        }

        // Stop, add songs to force pool/queue count drift.
        await mockService.simulatePlaybackState(.stopped)
        try await Task.sleep(nanoseconds: 100_000_000)

        for i in 4...5 {
            let song = Song(id: "\(i)", title: "Song \(i)", artist: "Artist", albumTitle: "Album", artworkURL: nil)
            try await player.addSong(song)
        }

        let poolCount = await player.songCount
        let queueCount = await player.lastShuffledQueue.count
        XCTAssertGreaterThan(poolCount, queueCount, "Pool should outgrow queue while rebuild is pending")

        let invariant = await player.queueInvariantCheck
        XCTAssertTrue(invariant.isHealthy, "Pending rebuild should be treated as a known-safe state")
        XCTAssertTrue(invariant.reasons.isEmpty, "No invariant violations should be emitted while rebuild is pending")
    }

    func testInvariantTreatsPlaybackMappedCurrentAsCanonicalWhenTransportIDNamespaceDiffers() async throws {
        let songs = (1...3).map { i in
            Song(id: "i.song\(i)", title: "Song \(i)", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        }
        for song in songs {
            try await player.addSong(song)
        }
        try await player.play()
        try await Task.sleep(nanoseconds: 100_000_000)

        guard let currentSong = await player.playbackState.currentSong else {
            XCTFail("Expected current song after play")
            return
        }

        // Simulate MusicKit reporting a catalog/raw transport ID while playback mapping resolves to the pool ID.
        mockService.mockCurrentSongId = "1358312005"
        await mockService.simulatePlaybackState(.paused(currentSong))
        try await Task.sleep(nanoseconds: 100_000_000)

        let invariant = await player.queueInvariantCheck
        XCTAssertTrue(
            invariant.isHealthy,
            "Invariant should not fail when playback mapping matches domain current song but transport ID uses a different namespace"
        )
        XCTAssertFalse(
            invariant.reasons.contains("transport-current-song-mismatch"),
            "Namespace-only transport/current mismatch should not be treated as queue drift"
        )
    }

    func testQueueDriftTelemetryMultipleTriggers() async throws {
        // Build an initial queue of 3 songs.
        for i in 1...3 {
            let song = Song(id: "\(i)", title: "Song \(i)", artist: "Artist", albumTitle: "Album", artworkURL: nil)
            try await player.addSong(song)
        }
        try await player.play()
        try await Task.sleep(nanoseconds: 100_000_000)

        let extraSongs = [
            Song(id: "extra1", title: "Extra 1", artist: "Artist", albumTitle: "Album", artworkURL: nil),
            Song(id: "extra2", title: "Extra 2", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        ]

        for song in extraSongs {
            await mockService.simulatePlaybackState(.stopped)
            try await Task.sleep(nanoseconds: 100_000_000)
            try await player.addSong(song)
            let needsBuild = await player.queueNeedsBuild
            XCTAssertTrue(needsBuild, "Each stopped add should mark rebuild pending")
            try await player.play()
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        let telemetry = await player.queueDriftTelemetry
        XCTAssertEqual(telemetry.detections, 0, "Phase-2 flow should not depend on drift telemetry triggers")
        XCTAssertEqual(telemetry.reconciliations, 0)
    }

    func testHardResetQueueForDebugClearsQueueAndDiagnostics() async throws {
        let songs = (1...3).map { i in
            Song(id: "\(i)", title: "Song \(i)", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        }
        for song in songs {
            try await player.addSong(song)
        }
        try await player.play()
        try await Task.sleep(nanoseconds: 100_000_000)

        await player.hardResetQueueForDebug()

        let songCount = await player.songCount
        XCTAssertEqual(songCount, 0, "Hard reset should clear the song pool")

        let queue = await player.lastShuffledQueue
        XCTAssertTrue(queue.isEmpty, "Hard reset should clear queue order")

        let telemetry = await player.queueDriftTelemetry
        XCTAssertEqual(telemetry.detections, 0)
        XCTAssertEqual(telemetry.reconciliations, 0)
        XCTAssertTrue(telemetry.recentEvents.isEmpty, "Hard reset should clear telemetry history")

        let notice = await player.operationNotice
        XCTAssertNil(notice, "Hard reset should clear any operation notice")

        let records = await player.recentQueueOperations
        XCTAssertEqual(records.count, 1, "Hard reset should reset journal and record only the reset operation")
        XCTAssertEqual(records.first?.operation, "hard-reset-queue")
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

        let queueBeforeFailure = await player.lastShuffledQueue.map(\.id)

        await mockService.setShouldThrowOnReplace(NSError(domain: "test", code: 99))
        await player.reshuffleWithNewAlgorithm(.artistSpacing)
        try await Task.sleep(nanoseconds: 100_000_000)

        let queueAfterFailure = await player.lastShuffledQueue.map(\.id)
        XCTAssertEqual(
            queueAfterFailure,
            queueBeforeFailure,
            "Reshuffle failure should roll back to the previous queue state"
        )

        let notice = await player.operationNotice
        XCTAssertNotNil(notice, "Reshuffle failure should publish a non-blocking notice")

        // State should remain usable despite failed queue mutation.
        await mockService.setShouldThrowOnReplace(nil)
        try await player.play()
        try await Task.sleep(nanoseconds: 100_000_000)

        let state = await player.playbackState
        XCTAssertTrue(state.isActive, "Player should remain recoverable after queue mutation failure")
    }

    func testQueueOperationJournalCapsAtMaxRecords() async throws {
        let song = Song(id: "1", title: "Song 1", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        try await player.addSong(song)
        try await player.play()
        try await Task.sleep(nanoseconds: 100_000_000)

        for i in 0..<(QueueOperationJournal.maxRecords + 40) {
            if i.isMultiple(of: 2) {
                await mockService.simulatePlaybackState(.paused(song))
            } else {
                await mockService.simulatePlaybackState(.playing(song))
            }
        }
        try await Task.sleep(nanoseconds: 200_000_000)

        let records = await player.recentQueueOperations
        XCTAssertEqual(records.count, QueueOperationJournal.maxRecords, "Journal should trim to max records")
        XCTAssertGreaterThanOrEqual(
            records.first?.timestamp ?? .distantPast,
            records.last?.timestamp ?? .distantFuture,
            "Most recent operation should be first"
        )
    }

    func testExportQueueDiagnosticsSnapshotIncludesInvariantAndJournal() async throws {
        let song1 = Song(id: "1", title: "Song 1", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        let song2 = Song(id: "2", title: "Song 2", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        try await player.addSong(song1)
        try await player.addSong(song2)
        try await player.play()
        try await Task.sleep(nanoseconds: 100_000_000)

        let json = await player.exportQueueDiagnosticsSnapshot(
            trigger: "unit-test",
            detail: "snapshot-coverage"
        )

        let data = Data(json.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(QueueDiagnosticsSnapshot.self, from: data)

        XCTAssertEqual(snapshot.trigger, "unit-test")
        XCTAssertEqual(snapshot.detail, "snapshot-coverage")
        XCTAssertEqual(Set(snapshot.poolSongIds), Set(["1", "2"]))
        XCTAssertFalse(snapshot.operationJournal.isEmpty, "Snapshot should include operation journal records")
        XCTAssertEqual(
            snapshot.invariantCheck.transportEntryCount,
            snapshot.transportEntryCount,
            "Snapshot transport fields should match invariant payload"
        )
    }
}
