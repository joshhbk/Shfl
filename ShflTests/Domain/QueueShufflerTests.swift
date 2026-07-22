import XCTest
@testable import Shfl

final class QueueShufflerTests: XCTestCase {

    private func makeSong(
        id: String,
        artist: String = "Artist",
        playCount: Int = 0,
        lastPlayedDate: Date? = nil
    ) -> Song {
        Song(
            id: id,
            title: "Song \(id)",
            artist: artist,
            albumTitle: "Album",
            artworkURL: nil,
            playCount: playCount,
            lastPlayedDate: lastPlayedDate
        )
    }

    // MARK: - Pure Random

    func testPureRandomCanProduceDuplicates() {
        let songs = (1...3).map { makeSong(id: "\($0)") }
        let shuffler = QueueShuffler(algorithm: .pureRandom)

        // With only 3 songs and 100 element output, duplicates are guaranteed
        let result = shuffler.shuffle(songs, count: 100)

        XCTAssertEqual(result.count, 100)
        let uniqueIds = Set(result.map(\.id))
        XCTAssertLessThanOrEqual(uniqueIds.count, 3)
    }

    func testPureRandomDefaultCountContainsAllSongsOnce() {
        let songs = (1...25).map { makeSong(id: "\($0)") }
        let shuffler = QueueShuffler(algorithm: .pureRandom)

        let result = shuffler.shuffle(songs)

        XCTAssertEqual(result.count, songs.count)
        XCTAssertEqual(Set(result.map(\.id)), Set(songs.map(\.id)))
    }

    // MARK: - No Repeat

    func testNoRepeatContainsAllSongsOnce() {
        let songs = (1...10).map { makeSong(id: "\($0)") }
        let shuffler = QueueShuffler(algorithm: .noRepeat)

        let result = shuffler.shuffle(songs)

        XCTAssertEqual(result.count, 10)
        XCTAssertEqual(Set(result.map(\.id)), Set(songs.map(\.id)))
    }

    func testNoRepeatShufflesOrder() {
        let songs = (1...20).map { makeSong(id: "\($0)") }
        let result = QueueShuffler(algorithm: .noRepeat, seed: 42)
            .shuffle(songs)
            .map(\.id)

        XCTAssertNotEqual(result, songs.map(\.id))
        XCTAssertEqual(
            result,
            QueueShuffler(algorithm: .noRepeat, seed: 42).shuffle(songs).map(\.id)
        )
    }

    // MARK: - Weighted by Recency

    func testWeightedByRecencyPrioritizesOlderSongs() {
        let now = Date()
        let songs = [
            makeSong(id: "recent", lastPlayedDate: now),
            makeSong(id: "old", lastPlayedDate: now.addingTimeInterval(-86400 * 30)),
            makeSong(id: "never", lastPlayedDate: nil)
        ]
        let result = QueueShuffler(algorithm: .weightedByRecency, seed: 5).shuffle(songs)
        XCTAssertEqual(result.map(\.id), ["never", "old", "recent"])
    }

    // MARK: - Weighted by Play Count

    func testWeightedByPlayCountPrioritizesLessPlayed() {
        let songs = [
            makeSong(id: "played100", playCount: 100),
            makeSong(id: "played10", playCount: 10),
            makeSong(id: "played0", playCount: 0)
        ]
        let result = QueueShuffler(algorithm: .weightedByPlayCount, seed: 5).shuffle(songs)
        XCTAssertEqual(result.map(\.id), ["played0", "played10", "played100"])
    }

    func testWeightedAlgorithmsDoNotFallBackToInsertionOrderForEqualMetadata() {
        let songs = (1...10).map { makeSong(id: "\($0)") }
        let insertionOrder = songs.map(\.id)

        let byCount = QueueShuffler(
            algorithm: .weightedByPlayCount,
            seed: 123
        ).shuffle(songs).map(\.id)
        let byRecency = QueueShuffler(
            algorithm: .weightedByRecency,
            seed: 123
        ).shuffle(songs).map(\.id)

        XCTAssertNotEqual(byCount, insertionOrder)
        XCTAssertNotEqual(byRecency, insertionOrder)
        XCTAssertEqual(Set(byCount), Set(insertionOrder))
        XCTAssertEqual(Set(byRecency), Set(insertionOrder))
    }

    // MARK: - Artist Spacing

    func testArtistSpacingAvoidsAdjacentSameArtist() {
        let songs = [
            makeSong(id: "a1", artist: "Artist A"),
            makeSong(id: "a2", artist: "Artist A"),
            makeSong(id: "b1", artist: "Artist B"),
            makeSong(id: "b2", artist: "Artist B"),
            makeSong(id: "c1", artist: "Artist C"),
            makeSong(id: "c2", artist: "Artist C")
        ]
        let shuffler = QueueShuffler(algorithm: .artistSpacing)

        // Run multiple times - should never have adjacent same artists (when avoidable)
        for _ in 0..<20 {
            let result = shuffler.shuffle(songs)

            for i in 0..<(result.count - 1) {
                let current = result[i].artist
                let next = result[i + 1].artist
                XCTAssertNotEqual(current, next, "Adjacent songs should have different artists")
            }
        }
    }

    func testArtistSpacingHandlesSingleArtist() {
        // When all songs are same artist, can't avoid adjacent
        let songs = (1...5).map { makeSong(id: "\($0)", artist: "Same Artist") }
        let shuffler = QueueShuffler(algorithm: .artistSpacing)

        let result = shuffler.shuffle(songs)

        // Should still return all songs
        XCTAssertEqual(result.count, 5)
        XCTAssertEqual(Set(result.map(\.id)), Set(songs.map(\.id)))
    }

    // MARK: - Edge Cases

    func testEmptyInput() {
        let shuffler = QueueShuffler(algorithm: .noRepeat)
        let result = shuffler.shuffle([])
        XCTAssertTrue(result.isEmpty)
    }

    func testSingleSong() {
        let songs = [makeSong(id: "only")]
        let shuffler = QueueShuffler(algorithm: .noRepeat)

        let result = shuffler.shuffle(songs)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].id, "only")
    }
}
