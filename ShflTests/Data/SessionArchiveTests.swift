import SwiftData
import XCTest
@testable import Shfl

@MainActor
final class SessionArchiveTests: XCTestCase {
    private var container: ModelContainer!
    private var archive: SessionArchive!

    private enum InjectedFailure: Error { case save }

    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: PersistedSession.self, configurations: config)
        archive = SessionArchive(modelContext: container.mainContext)
    }

    override func tearDown() {
        container = nil
        archive = nil
    }

    func testLoadReturnsEmptyWhenNothingPersisted() async throws {
        let loaded = try await archive.loadAsync()
        XCTAssertEqual(loaded, .empty)
    }

    func testCommitAndLoadRoundTripsPoolAndSession() async throws {
        let songs = makeSongs(3)
        let record = makeRecord(songs: songs, currentIndex: 1)
            .checkpointed(position: 42, at: Date())

        try archive.commit(pool: songs, session: record)

        let loaded = try await archive.loadAsync()
        XCTAssertEqual(loaded.pool, songs)
        XCTAssertEqual(loaded.session, record)
    }

    func testCommitReplacesPreviousRecord() async throws {
        let first = makeSongs(2)
        try archive.commit(pool: first, session: makeRecord(songs: first, currentIndex: 0))

        let second = makeSongs(3)
        try archive.commit(pool: second, session: nil)

        let loaded = try archive.load()
        XCTAssertEqual(loaded.pool, second)
        XCTAssertNil(loaded.session)
    }

    func testSessionRestoresWhenPoolHasDrifted() async throws {
        let sessionSongs = makeSongs(2)
        let record = makeRecord(songs: sessionSongs, currentIndex: 1)

        // The draft pool grows after the session was captured.
        let driftedPool = sessionSongs + makeSongs(3)
        try archive.commit(pool: driftedPool, session: record)

        let loaded = try archive.load()
        XCTAssertEqual(loaded.session?.songOrder, sessionSongs)
        XCTAssertEqual(loaded.session?.currentSongID, sessionSongs[1].id)
    }

    func testClearActiveSessionKeepsPool() async throws {
        let songs = makeSongs(2)
        try archive.commit(pool: songs, session: makeRecord(songs: songs, currentIndex: 0))

        try archive.clearActiveSession()

        let loaded = try archive.load()
        XCTAssertEqual(loaded.pool, songs)
        XCTAssertNil(loaded.session)
    }

    func testFailedCommitKeepsPreviousRecordRecoverable() async throws {
        let original = makeSongs(1)
        try archive.commit(pool: original, session: makeRecord(songs: original, currentIndex: 0))

        let failing = SessionArchive(
            modelContext: container.mainContext,
            saveHandler: { throw InjectedFailure.save }
        )
        let replacement = makeSongs(2)

        XCTAssertThrowsError(try failing.commit(pool: replacement, session: nil))

        let recovered = SessionArchive(modelContext: ModelContext(container))
        let loaded = try await recovered.loadAsync()
        XCTAssertEqual(loaded.pool, original)
        XCTAssertNotNil(loaded.session)
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

    private func makeRecord(songs: [Song], currentIndex: Int) -> ListeningSessionRecord {
        let session = ListeningSession(
            songOrder: songs,
            algorithm: .noRepeat,
            seed: 7
        )
        return ListeningSessionRecord.make(
            session: session,
            currentSongID: songs[currentIndex].id,
            playbackPosition: 0,
            savedAt: Date()
        )!
    }
}