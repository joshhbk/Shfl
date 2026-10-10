import XCTest
@testable import Shfl

@MainActor
final class SessionDraftStoreTests: XCTestCase {
    private func makeSongs(_ count: Int, start: Int = 1) -> [Song] {
        (start..<(start + count)).map { index in
            Song(
                id: "\(index)",
                title: "Song \(index)",
                artist: "Artist \(index)",
                albumTitle: "Album",
                artworkURL: nil
            )
        }
    }

    // MARK: - Membership and capacity

    func test_addingSkipsSongsAlreadyInThePool() throws {
        let draft = SessionDraftStore()
        try draft.add(makeSongs(2))

        try draft.add(makeSongs(3))

        XCTAssertEqual(draft.songs.map(\.id), ["1", "2", "3"])
        XCTAssertTrue(draft.contains("2"))
        XCTAssertFalse(draft.contains("99"))
    }

    func test_addingPastCapacityThrowsAndChangesNothing() throws {
        let draft = SessionDraftStore()
        try draft.add(makeSongs(SessionDraft.maxSongs - 1))

        XCTAssertThrowsError(try draft.add(makeSongs(2, start: 500))) { error in
            XCTAssertEqual(error as? ShufflePlayerError, .capacityReached)
        }
        XCTAssertEqual(draft.songCount, SessionDraft.maxSongs - 1)
        XCTAssertEqual(draft.remainingCapacity, 1)
        XCTAssertFalse(draft.isAtCapacity)
    }

    func test_removeAllKeepsTheStagedAlgorithm() throws {
        let draft = SessionDraftStore(algorithm: .artistSpacing)
        try draft.add(makeSongs(3))

        draft.removeAll()

        XCTAssertTrue(draft.isEmpty)
        XCTAssertEqual(draft.algorithm, .artistSpacing)
    }

    // MARK: - Autofill

    func test_autofillFillsOnlyTheRemainingCapacity() async throws {
        let draft = SessionDraftStore()
        try draft.add(makeSongs(SessionDraft.maxSongs - 20))
        let source = StubAutofillSource(songs: makeSongs(50, start: 1_000))

        let added = try await draft.autofill(from: source)

        XCTAssertEqual(added, 20)
        XCTAssertTrue(draft.isAtCapacity)
        let request = source.lastRequest
        XCTAssertEqual(request?.limit, 20)
        XCTAssertEqual(request?.excluding.count, SessionDraft.maxSongs - 20)
    }

    func test_autofillWhenFullDoesNotAskTheSource() async throws {
        let draft = SessionDraftStore()
        try draft.add(makeSongs(SessionDraft.maxSongs))
        let source = StubAutofillSource(songs: makeSongs(5, start: 1_000))

        let added = try await draft.autofill(from: source)

        XCTAssertEqual(added, 0)
        let request = source.lastRequest
        XCTAssertNil(request)
    }

    func test_autofillSkipsSongsAddedWhileItWasFetching() async throws {
        let draft = SessionDraftStore()
        let songs = makeSongs(3)
        let source = StubAutofillSource(songs: songs, beforeReturning: {
            try? draft.add(songs[0])
        })

        let added = try await draft.autofill(from: source)

        XCTAssertEqual(added, 2)
        XCTAssertEqual(draft.songs.map(\.id), ["1", "2", "3"])
    }

    // MARK: - Change stream

    func test_songPoolChangesFiresForMembershipButNotAlgorithm() async throws {
        let draft = SessionDraftStore()
        var fired = 0
        let changes = draft.songPoolChanges
        let task = Task { @MainActor in
            for await _ in changes { fired += 1 }
        }
        defer { task.cancel() }

        draft.stage(.artistSpacing)
        try draft.add(makeSongs(2))
        draft.remove(songID: "1")
        draft.remove(songID: "missing")
        await waitForStateUpdate()

        XCTAssertEqual(fired, 2)
    }

    func test_algorithmChangesYieldsEachDifferentAlgorithmButNotMembership() async throws {
        let draft = SessionDraftStore(algorithm: .noRepeat)
        var staged: [ShuffleAlgorithm] = []
        let changes = draft.algorithmChanges
        let task = Task { @MainActor in
            for await algorithm in changes { staged.append(algorithm) }
        }
        defer { task.cancel() }

        draft.stage(.noRepeat)
        try draft.add(makeSongs(2))
        draft.stage(.artistSpacing)
        draft.stage(.artistSpacing)
        draft.stage(.weightedByPlayCount)
        await waitForStateUpdate()

        XCTAssertEqual(staged, [.artistSpacing, .weightedByPlayCount])
    }
}

@MainActor
private final class StubAutofillSource: AutofillSource {
    struct Request {
        let excluding: Set<String>
        let limit: Int
    }

    private let songs: [Song]
    private let beforeReturning: () -> Void
    private(set) var lastRequest: Request?

    init(songs: [Song], beforeReturning: @escaping () -> Void = {}) {
        self.songs = songs
        self.beforeReturning = beforeReturning
    }

    func fetchSongs(excluding: Set<String>, limit: Int) async throws -> [Song] {
        lastRequest = Request(excluding: excluding, limit: limit)
        await Task.yield()
        beforeReturning()
        return Array(songs.filter { !excluding.contains($0.id) }.prefix(limit))
    }
}
