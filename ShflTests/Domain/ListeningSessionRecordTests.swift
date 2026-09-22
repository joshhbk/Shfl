import XCTest
@testable import Shfl

@MainActor
final class ListeningSessionRecordTests: XCTestCase {
    func testRestoredReturnsSessionForValidRecord() {
        let songs = makeSongs(3)
        let record = makeRecord(songs: songs, currentIndex: 1, savedAt: Date())

        guard case .restore(let session, let currentSongID, _, let position) = record.restored() else {
            return XCTFail("Expected a restore decision")
        }
        XCTAssertEqual(session.songOrder, songs)
        XCTAssertEqual(currentSongID, songs[1].id)
        XCTAssertEqual(position, 12)
    }

    func testRestoredPreservesSessionIdentity() {
        let songs = makeSongs(2)
        let id = UUID()
        let record = ListeningSessionRecord(
            sessionID: id,
            songOrder: songs,
            algorithm: .noRepeat,
            seed: 3,
            currentSongID: songs[0].id,
            playedSongIDs: [],
            playbackPosition: 0,
            savedAt: Date()
        )

        guard case .restore(let session, _, _, _) = record.restored() else {
            return XCTFail("Expected a restore decision")
        }
        XCTAssertEqual(session.id, id)
    }

    func testRestoredDiscardsEmptyQueue() {
        let record = ListeningSessionRecord(
            songOrder: [],
            algorithm: .noRepeat,
            seed: 1,
            currentSongID: "missing",
            playedSongIDs: [],
            playbackPosition: 0,
            savedAt: Date()
        )
        XCTAssertEqual(record.restored(), .discard(.emptyQueue))
    }

    func testRestoredDiscardsStaleRecord() {
        let songs = makeSongs(1)
        let stale = Date().addingTimeInterval(-(ListeningSessionRecord.staleAfter + 60))
        let record = makeRecord(songs: songs, currentIndex: 0, savedAt: stale)

        XCTAssertEqual(record.restored(), .discard(.stale))
    }

    func testRestoredDiscardsWhenCurrentSongMissing() {
        let songs = makeSongs(2)
        let record = ListeningSessionRecord(
            songOrder: songs,
            algorithm: .noRepeat,
            seed: 1,
            currentSongID: "not-in-queue",
            playedSongIDs: [],
            playbackPosition: 0,
            savedAt: Date()
        )
        XCTAssertEqual(record.restored(), .discard(.currentSongMissing))
    }

    func testRecordSurvivesCodableRoundTrip() throws {
        let record = makeRecord(songs: makeSongs(3), currentIndex: 1, savedAt: Date())

        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(ListeningSessionRecord.self, from: data)

        XCTAssertEqual(decoded, record)
    }

    private func makeSongs(_ count: Int) -> [Song] {
        (0..<count).map {
            Song(
                id: "song-\($0)",
                title: "Song \($0)",
                artist: "Artist \($0 % 3)",
                albumTitle: "Album",
                artworkURL: nil
            )
        }
    }

    private func makeRecord(songs: [Song], currentIndex: Int, savedAt: Date) -> ListeningSessionRecord {
        let session = ListeningSession(songOrder: songs, algorithm: .noRepeat, seed: 7)
        return ListeningSessionRecord.make(
            session: session,
            currentSongID: songs[currentIndex].id,
            playbackPosition: 12,
            savedAt: savedAt
        )!
    }
}