import XCTest
@testable import Shfl

final class QueueStateTests: XCTestCase {

    private func makeSong(id: String, artist: String = "Artist") -> Song {
        Song(
            id: id,
            title: "Song \(id)",
            artist: artist,
            albumTitle: "Album",
            artworkURL: nil,
            playCount: 0,
            lastPlayedDate: nil
        )
    }

    // MARK: - Initialization

    func testEmptyStateIsEmpty() {
        let state = QueueState.empty

        XCTAssertTrue(state.isEmpty)
        XCTAssertEqual(state.songCount, 0)
        XCTAssertNil(state.currentSong)
        XCTAssertFalse(state.hasQueue)
    }

    // MARK: - Adding Songs

    func testAddingSong() {
        let state = QueueState.empty
        let song = makeSong(id: "1")

        let newState = state.addingSong(song)

        XCTAssertNotNil(newState)
        XCTAssertEqual(newState?.songCount, 1)
        XCTAssertTrue(newState?.containsSong(id: "1") ?? false)
    }

    func testAddingSongAtCapacity() {
        var state = QueueState.empty
        for i in 0..<120 {
            state = state.addingSong(makeSong(id: "\(i)"))!
        }

        let extraSong = makeSong(id: "extra")
        let newState = state.addingSong(extraSong)

        XCTAssertNil(newState, "Should return nil when at capacity")
    }

    func testAddingDuplicateSongReturnsSameState() {
        let song = makeSong(id: "1")
        let state = QueueState.empty.addingSong(song)!

        let newState = state.addingSong(song)

        XCTAssertNotNil(newState)
        XCTAssertEqual(newState?.songCount, 1, "Duplicate should not increase count")
    }

    func testAddingMultipleSongs() {
        let state = QueueState.empty
        let songs = (1...5).map { makeSong(id: "\($0)") }

        let newState = state.addingSongs(songs)

        XCTAssertNotNil(newState)
        XCTAssertEqual(newState?.songCount, 5)
    }

    func testAddingMultipleSongsExceedingCapacity() {
        var state = QueueState.empty
        for i in 0..<118 {
            state = state.addingSong(makeSong(id: "\(i)"))!
        }

        let newSongs = (200...205).map { makeSong(id: "\($0)") }
        let newState = state.addingSongs(newSongs)

        XCTAssertNil(newState, "Should return nil when batch exceeds capacity")
    }

    // MARK: - Removing Songs

    func testRemovingSong() {
        let songs = (1...3).map { makeSong(id: "\($0)") }
        let state = QueueState.empty.addingSongs(songs)!

        let newState = state.removingSong(id: "2")

        XCTAssertEqual(newState.songCount, 2)
        XCTAssertFalse(newState.containsSong(id: "2"))
        XCTAssertTrue(newState.containsSong(id: "1"))
        XCTAssertTrue(newState.containsSong(id: "3"))
    }

    func testRemovingSongFromQueue() {
        let songs = (1...3).map { makeSong(id: "\($0)") }
        let state = QueueState.empty.addingSongs(songs)!.shuffled()

        let newState = state.removingSong(id: "2")

        XCTAssertFalse(newState.queueOrder.contains { $0.id == "2" })
    }

    func testCleared() {
        let songs = (1...5).map { makeSong(id: "\($0)") }
        let state = QueueState.empty.addingSongs(songs)!.shuffled()

        let clearedState = state.cleared()

        XCTAssertTrue(clearedState.isEmpty)
        XCTAssertFalse(clearedState.hasQueue)
        XCTAssertTrue(clearedState.playedIds.isEmpty)
    }

    // MARK: - Shuffling

    func testShuffled() {
        let songs = (1...10).map { makeSong(id: "\($0)") }
        let state = QueueState.empty.addingSongs(songs)!

        let shuffledState = state.shuffled()

        XCTAssertTrue(shuffledState.hasQueue)
        XCTAssertEqual(shuffledState.queueOrder.count, 10)
        XCTAssertEqual(shuffledState.currentIndex, 0)
        XCTAssertTrue(shuffledState.playedIds.isEmpty, "Fresh shuffle clears history")
    }

    func testShuffledWithAlgorithm() {
        let songs = (1...10).map { makeSong(id: "\($0)") }
        let state = QueueState.empty.addingSongs(songs)!

        let shuffledState = state.shuffled(with: .artistSpacing)

        XCTAssertEqual(shuffledState.algorithm, .artistSpacing)
    }

    func testReshuffledUpcomingPreservesCurrentSong() {
        let songs = (1...5).map { makeSong(id: "\($0)") }
        var state = QueueState.empty.addingSongs(songs)!.shuffled()
        let originalCurrentSong = state.currentSong

        state = state.reshuffledUpcoming()

        XCTAssertEqual(state.currentSong?.id, originalCurrentSong?.id)
        XCTAssertEqual(state.currentIndex, 0)
    }

    func testReshuffledUpcomingPreservesInvariantAndKeepsPlayedBeforeCurrent() {
        let songs = (1...5).map { makeSong(id: "\($0)") }
        var state = QueueState.empty.addingSongs(songs)!.shuffled()

        // Simulate playing through first two songs
        state = state.advancedToNext()
        state = state.advancedToNext()

        // Now reshuffle upcoming
        let newState = state.reshuffledUpcoming()
        let playedSongIds = state.playedIds

        XCTAssertEqual(newState.queueOrder.count, state.songPool.count, "Queue should still include full pool")
        XCTAssertEqual(Set(newState.queueOrderIds), Set(state.songPool.map(\.id)), "Queue IDs should match pool IDs")
        XCTAssertEqual(newState.currentSongId, state.currentSongId, "Current song should be preserved")

        // Played songs should remain before current to preserve continuity.
        for playedId in playedSongIds {
            guard let playedIndex = newState.queueOrder.firstIndex(where: { $0.id == playedId }) else {
                XCTFail("Played song \(playedId) should still exist in queue")
                continue
            }
            XCTAssertLessThan(playedIndex, newState.currentIndex, "Played song \(playedId) should be before current")
        }
    }

    // MARK: - Navigation

    func testAdvancedToNext() {
        let songs = (1...3).map { makeSong(id: "\($0)") }
        let state = QueueState.empty.addingSongs(songs)!.shuffled()
        let firstSongId = state.currentSongId

        let newState = state.advancedToNext()

        XCTAssertEqual(newState.currentIndex, 1)
        XCTAssertNotEqual(newState.currentSongId, firstSongId)
        XCTAssertTrue(newState.playedIds.contains(firstSongId!), "First song should be in history")
    }

    func testAdvancedToNextAtEnd() {
        let songs = (1...2).map { makeSong(id: "\($0)") }
        var state = QueueState.empty.addingSongs(songs)!.shuffled()
        state = state.advancedToNext() // Now at last song

        let newState = state.advancedToNext()

        XCTAssertEqual(newState.currentIndex, state.currentIndex, "Should not advance past end")
    }

    func testRevertedToPrevious() {
        let songs = (1...3).map { makeSong(id: "\($0)") }
        var state = QueueState.empty.addingSongs(songs)!.shuffled()
        state = state.advancedToNext()
        let secondSongId = state.currentSongId

        let newState = state.revertedToPrevious()

        XCTAssertEqual(newState.currentIndex, 0)
        XCTAssertFalse(newState.playedIds.contains(newState.currentSongId!),
                       "Current song should be removed from history when going back")
    }

    func testRevertedToPreviousAtStart() {
        let songs = (1...2).map { makeSong(id: "\($0)") }
        let state = QueueState.empty.addingSongs(songs)!.shuffled()

        let newState = state.revertedToPrevious()

        XCTAssertEqual(newState.currentIndex, 0, "Should not go before start")
    }

    func testHasNextAndHasPrevious() {
        let songs = (1...3).map { makeSong(id: "\($0)") }
        var state = QueueState.empty.addingSongs(songs)!.shuffled()

        XCTAssertTrue(state.hasNext)
        XCTAssertFalse(state.hasPrevious)

        state = state.advancedToNext()
        XCTAssertTrue(state.hasNext)
        XCTAssertTrue(state.hasPrevious)

        state = state.advancedToNext()
        XCTAssertFalse(state.hasNext)
        XCTAssertTrue(state.hasPrevious)
    }

    // MARK: - Played History

    func testMarkingAsPlayed() {
        let songs = (1...3).map { makeSong(id: "\($0)") }
        let state = QueueState.empty.addingSongs(songs)!.shuffled()

        let newState = state.markingAsPlayed(id: "1")

        XCTAssertTrue(newState.hasPlayed(id: "1"))
    }

    func testClearingPlayedHistory() {
        let songs = (1...3).map { makeSong(id: "\($0)") }
        var state = QueueState.empty.addingSongs(songs)!.shuffled()
        state = state.advancedToNext()
        state = state.advancedToNext()

        let clearedState = state.clearingPlayedHistory()

        XCTAssertTrue(clearedState.playedIds.isEmpty)
        XCTAssertEqual(clearedState.currentIndex, state.currentIndex, "Index unchanged")
    }

    // MARK: - Restoration

    func testRestored() {
        let songs = (1...5).map { makeSong(id: "\($0)") }
        let state = QueueState.empty.addingSongs(songs)!

        let restoredState = state.restored(
            queueOrder: ["3", "4", "5", "1", "2"],
            currentSongId: "4",
            playedIds: ["3"]
        )

        XCTAssertNotNil(restoredState)
        XCTAssertEqual(restoredState?.currentSongId, "4")
        XCTAssertEqual(restoredState?.currentIndex, 1)
        XCTAssertEqual(restoredState?.queueOrderIds, ["3", "4", "5", "1", "2"])
        XCTAssertTrue(restoredState?.hasPlayed(id: "3") ?? false)
    }

    func testRestoredWithMissingSongs() {
        // Only have songs 1, 3, 5
        let songs = [makeSong(id: "1"), makeSong(id: "3"), makeSong(id: "5")]
        let state = QueueState.empty.addingSongs(songs)!

        let restoredState = state.restored(
            queueOrder: ["1", "2", "3", "4", "5"], // 2 and 4 don't exist
            currentSongId: "3",
            playedIds: ["1", "2"] // 2 doesn't exist
        )

        XCTAssertNotNil(restoredState)
        XCTAssertEqual(restoredState?.queueOrder.count, 3) // Only valid songs
        XCTAssertEqual(restoredState?.currentSongId, "3")
        XCTAssertTrue(restoredState?.hasPlayed(id: "1") ?? false)
        XCTAssertFalse(restoredState?.hasPlayed(id: "2") ?? true) // Invalid song filtered out
    }

    func testRestoredWithEmptyPool() {
        let state = QueueState.empty

        let restoredState = state.restored(
            queueOrder: ["1", "2", "3"],
            currentSongId: "1",
            playedIds: []
        )

        XCTAssertNil(restoredState, "Should fail with empty pool")
    }

    func testRestoredWithNoValidSongs() {
        let songs = [makeSong(id: "a"), makeSong(id: "b")]
        let state = QueueState.empty.addingSongs(songs)!

        let restoredState = state.restored(
            queueOrder: ["1", "2", "3"], // None exist in pool
            currentSongId: "1",
            playedIds: []
        )

        XCTAssertNil(restoredState, "Should fail when no valid songs in queue")
    }

    func testRestoredFallsBackToFirstSongWhenCurrentMissing() {
        let songs = (1...3).map { makeSong(id: "\($0)") }
        let state = QueueState.empty.addingSongs(songs)!

        let restoredState = state.restored(
            queueOrder: ["1", "2", "3"],
            currentSongId: "missing",
            playedIds: []
        )

        XCTAssertNotNil(restoredState)
        XCTAssertEqual(restoredState?.currentIndex, 0)
        XCTAssertEqual(restoredState?.currentSongId, "1")
    }

    // MARK: - Persistence Helpers

    func testQueueOrderIds() {
        let songs = (1...3).map { makeSong(id: "\($0)") }
        let state = QueueState.empty.addingSongs(songs)!.shuffled()

        let ids = state.queueOrderIds

        XCTAssertEqual(ids.count, 3)
        XCTAssertEqual(Set(ids), Set(["1", "2", "3"]))
    }

    func testHasRestorableState() {
        let emptyState = QueueState.empty
        XCTAssertFalse(emptyState.hasRestorableState)

        let withSongs = emptyState.addingSongs([makeSong(id: "1")])!
        XCTAssertFalse(withSongs.hasRestorableState, "No queue yet")

        let shuffled = withSongs.shuffled()
        XCTAssertTrue(shuffled.hasRestorableState)
    }

    // MARK: - Queue-Only Removal (Rollback)

    func testRemovingFromQueueOnlyKeepsPool() {
        let songs = (1...3).map { makeSong(id: "\($0)") }
        let state = QueueState.empty.addingSongs(songs)!.shuffled()

        let newState = state.removingFromQueueOnly(id: "2")

        // Song should still be in pool
        XCTAssertTrue(newState.containsSong(id: "2"), "Song should remain in pool")
        // But not in queue
        XCTAssertFalse(newState.queueOrder.contains { $0.id == "2" }, "Song should be removed from queue")
        // Other queue items preserved
        XCTAssertEqual(newState.queueOrder.count, 2)
    }

    // MARK: - Queue Invalidation

    func testInvalidatingQueueKeepsPool() {
        let songs = (1...5).map { makeSong(id: "\($0)") }
        let state = QueueState.empty.addingSongs(songs)!.shuffled()

        let invalidated = state.invalidatingQueue()

        XCTAssertEqual(invalidated.songCount, 5, "Pool should be preserved")
        XCTAssertFalse(invalidated.hasQueue, "Queue should be cleared")
        XCTAssertTrue(invalidated.playedIds.isEmpty, "Played history should be cleared")
        XCTAssertTrue(invalidated.containsSong(id: "1"), "Songs should still be in pool")
    }

    // MARK: - Queue Staleness

    func testIsQueueStaleWhenPoolChanged() {
        let songs = (1...3).map { makeSong(id: "\($0)") }
        var state = QueueState.empty.addingSongs(songs)!.shuffled()

        // Add a new song to pool (not in queue)
        state = state.addingSong(makeSong(id: "4"))!

        XCTAssertTrue(state.isQueueStale, "Queue should be stale when pool has songs not in queue")
    }

    func testIsQueueStaleReturnsFalseWhenSynced() {
        let songs = (1...3).map { makeSong(id: "\($0)") }
        let state = QueueState.empty.addingSongs(songs)!.shuffled()

        XCTAssertFalse(state.isQueueStale, "Queue should not be stale when pool matches queue")
    }

    func testIsQueueStaleReturnsFalseWhenNoQueue() {
        let songs = (1...3).map { makeSong(id: "\($0)") }
        let state = QueueState.empty.addingSongs(songs)!

        XCTAssertFalse(state.isQueueStale, "Should not be stale when there's no queue")
    }

    func testIsQueueStaleWhenSongRemoved() {
        let songs = (1...5).map { makeSong(id: "\($0)") }
        var state = QueueState.empty.addingSongs(songs)!.shuffled()

        // Remove a song (removes from both pool and queue)
        state = state.removingSong(id: "3")

        // After removing from both, they should be in sync
        XCTAssertFalse(state.isQueueStale, "Should not be stale after removing from both pool and queue")
    }

    func testIsQueueStaleWhenQueueContainsDuplicates() {
        let songs = (1...3).map { makeSong(id: "\($0)") }
        let state = QueueState(
            songPool: songs,
            queueOrder: [songs[0], songs[0], songs[1]],
            playedIds: [],
            currentIndex: 0,
            algorithm: .noRepeat
        )

        XCTAssertTrue(state.isQueueStale, "Queue should be stale when duplicate IDs are present")
    }

    func testReconcilingQueueRepairsMissingAndDuplicateEntries() {
        let songs = (1...5).map { makeSong(id: "\($0)") }
        let drifted = QueueState(
            songPool: songs,
            queueOrder: [songs[2], songs[2], songs[0]], // duplicate + missing entries
            playedIds: ["1"],
            currentIndex: 0,
            algorithm: .noRepeat
        )

        let repaired = drifted.reconcilingQueue(preferredCurrentSongId: "3")

        XCTAssertFalse(repaired.isQueueStale, "Repaired queue should be fully in sync with pool")
        XCTAssertEqual(repaired.queueOrder.count, songs.count, "Repaired queue should include full pool")
        XCTAssertEqual(Set(repaired.queueOrderIds), Set(songs.map(\.id)))
        XCTAssertEqual(repaired.currentSongId, "3", "Preferred current song should be preserved")
        XCTAssertEqual(repaired.queueOrder.first?.id, "1", "Played songs should be positioned before current")
    }

    // MARK: - Equatable

    func testEquatable() {
        let songs = (1...3).map { makeSong(id: "\($0)") }
        let state1 = QueueState.empty.addingSongs(songs)!.shuffled(with: .noRepeat)
        let state2 = QueueState(
            songPool: songs,
            queueOrder: state1.queueOrder,
            playedIds: state1.playedIds,
            currentIndex: state1.currentIndex,
            algorithm: .noRepeat
        )

        XCTAssertEqual(state1, state2)
    }
}
