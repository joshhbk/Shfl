import SwiftData
import XCTest
@testable import ShflCore
@testable import ShflDeterministic
import ShflTestSupport

@MainActor
final class ListeningSessionHostTests: XCTestCase {
    private var container: ModelContainer!
    private var modelContext: ModelContext!
    private var archive: SessionArchive!
    private var mockService: DeterministicMusicService!

    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: PersistedSession.self,
            configurations: config
        )
        modelContext = container.mainContext
        archive = SessionArchive(modelContext: modelContext)
        mockService = DeterministicMusicService()
    }

    override func tearDown() {
        container = nil
        modelContext = nil
        archive = nil
        mockService = nil
    }

    func testSceneDidLeaveForegroundCheckpointsSession() async throws {
        let host = makeHost()
        let player = host.player

        let song = Song(
            id: "1",
            title: "Song 1",
            artist: "Artist 1",
            albumTitle: "Album 1",
            artworkURL: nil
        )

        try host.sessionDraft.add(song)
        try await player.startFreshShuffle(seed: 5)
        await waitUntil { (try? self.archive.load().session) != nil }

        await mockService.setPlaybackTime(42)
        host.sceneDidLeaveForeground()

        let saved = try archive.load()
        XCTAssertEqual(saved.pool.map(\.id), ["1"])
        XCTAssertEqual(saved.session?.currentSongID, "1")
        XCTAssertEqual(saved.session?.playbackPosition, 42)
    }

    func testDraftEditsPersistWithoutAnExplicitSave() async throws {
        let songs = ["one", "two"].map {
            Song(id: $0, title: $0, artist: "Artist", albumTitle: "Album", artworkURL: nil)
        }
        let host = makeHost()

        try host.sessionDraft.add(songs)
        await waitUntil { (try? self.archive.load().pool.map(\.id)) == ["one", "two"] }

        // A swipe-dismissed sheet never reports back; the edit alone must be durable.
        host.sessionDraft.remove(songID: "one")
        await waitUntil { (try? self.archive.load().pool.map(\.id)) == ["two"] }
    }

    func testFreshShuffleAndDraftEditRestoreOnNextLaunch() async throws {
        let song = Song(id: "one", title: "One", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        let host = makeHost()

        // Same ordering as a fresh shuffle from the host: add then start, no yield between.
        try host.sessionDraft.add([song])
        try await host.player.startFreshShuffle(seed: 7)
        await waitUntil { (try? self.archive.load().session?.seed) == 7 }
        await waitForStateUpdate()

        let nextTransport = DeterministicMusicService()
        let nextHost = ListeningSessionHost(
            playbackTransport: nextTransport,
            archive: SessionArchive(modelContext: ModelContext(container)),
            autofillSource: StubAutofillSource(songs: [])
        )
        let restored = await nextHost.restoreSavedSession()
        XCTAssertTrue(restored)
        XCTAssertEqual(nextHost.sessionDraft.songs, [song])
        XCTAssertEqual(nextHost.player.playbackState, .paused(song))
        XCTAssertEqual(nextHost.player.activeSession?.seed, 7)
        withExtendedLifetime(host) {}
    }

    func testDraftEditPreservesPausedRestoredSession() async throws {
        let song = Song(id: "one", title: "One", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        let added = Song(id: "two", title: "Two", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        let session = ListeningSession(songOrder: [song], algorithm: .noRepeat, seed: 7)
        let record = try XCTUnwrap(ListeningSessionRecord.make(
            session: session, currentSongID: song.id, playbackPosition: 42, savedAt: Date()
        ))
        try archive.commit(pool: [song], session: record)
        let host = makeHost()
        await host.restoreSavedSession()

        try host.sessionDraft.add(added)
        await waitUntil { (try? self.archive.load().pool.count) == 2 }
        XCTAssertEqual(try archive.load().session, record)
    }

    func testStaleSessionIsClearedButPoolIsKept() async throws {
        let song = Song(id: "one", title: "One", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        let session = ListeningSession(songOrder: [song], algorithm: .noRepeat, seed: 7)
        let savedAt = Date()
        let record = try XCTUnwrap(ListeningSessionRecord.make(
            session: session, currentSongID: song.id, playbackPosition: 42, savedAt: savedAt
        ))
        try archive.commit(pool: [song], session: record)
        let host = makeHost(now: { savedAt.addingTimeInterval(ListeningSessionRecord.staleAfter + 1) })

        let restored = await host.restoreSavedSession()

        XCTAssertFalse(restored)
        XCTAssertEqual(host.sessionDraft.songs, [song])
        let saved = try archive.load()
        XCTAssertEqual(saved.pool, [song])
        XCTAssertNil(saved.session)
    }

    func testRemoveAllThenCheckpointDoesNotReviveSession() async throws {
        let song = Song(id: "one", title: "One", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        let host = makeHost()
        try host.sessionDraft.add([song])
        try await host.player.startFreshShuffle(seed: 7)
        await waitUntil { (try? self.archive.load().session) != nil }

        host.sessionDraft.removeAll()
        await host.player.clearSession()
        await waitUntil { (try? self.archive.load().session) == nil }
        await waitForStateUpdate()
        host.sceneDidLeaveForeground()
        let saved = try archive.load()
        XCTAssertTrue(saved.pool.isEmpty)
        XCTAssertNil(saved.session)
    }

    func testCheckpointCapturesNewSelectionInsteadOfLastStartedSong() async throws {
        let songs = ["one", "two"].map {
            Song(id: $0, title: $0, artist: "Artist", albumTitle: "Album", artworkURL: nil)
        }
        let host = makeHost()
        let player = host.player
        try host.sessionDraft.add(songs)
        try await player.startFreshShuffle(seed: 7)
        await waitUntil { (try? self.archive.load().session) != nil }
        let previousID = try XCTUnwrap(archive.load().session?.currentSongID)
        let selectedID = try XCTUnwrap(songs.first { $0.id != previousID }?.id)
        let session = try XCTUnwrap(player.activeSession)
        let restored = await player.restore(session, currentSongID: selectedID, playbackPosition: 23)
        XCTAssertTrue(restored)
        host.sceneDidLeaveForeground()
        let saved = try archive.load()
        XCTAssertEqual(saved.session?.currentSongID, selectedID)
        XCTAssertEqual(saved.session?.playbackPosition, 23)
    }

    func testUnrecognizedTransportSongDoesNotEraseLastValidSession() async throws {
        let librarySong = Song(id: "i.library", title: "Song", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        let catalogSong = Song(id: "123456", title: "Song", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        let host = makeHost()
        let player = host.player
        try host.sessionDraft.add([librarySong])
        try await player.startFreshShuffle(seed: 7)
        await waitUntil { (try? self.archive.load().session) != nil }
        let validRecord = try XCTUnwrap(archive.load().session)

        // MusicKit can surface the catalog representation of a library song.
        // An unrecognized report must not be interpreted as an explicit clear.
        await mockService.simulatePlaybackState(.playing(catalogSong))
        await waitUntil { player.playbackState.currentSongId == catalogSong.id }
        host.sceneDidLeaveForeground()
        XCTAssertEqual(try archive.load().session, validRecord)
    }

    func testStagingAnAlgorithmSavesIt() async {
        var saved: [ShuffleAlgorithm] = []
        let host = makeHost(saveAlgorithm: { saved.append($0) })

        host.sessionDraft.stage(.artistSpacing)
        await waitUntil { saved == [.artistSpacing] }

        XCTAssertEqual(saved, [.artistSpacing])
    }

    func testSceneDidLeaveForegroundRunsOnePersistencePass() async throws {
        var persistCallCount = 0
        let host = makeHost(lifecyclePersistenceHook: { persistCallCount += 1 })

        host.sceneDidLeaveForeground()

        XCTAssertEqual(persistCallCount, 1)
    }

    func testTransitionsDriveScrobblingAndPersistenceAcrossRestoreResumeAndFreshShuffle() async throws {
        let host = makeHost()
        let player = host.player
        let nowPlaying = expectation(description: "Now playing for each listening session")
        nowPlaying.expectedFulfillmentCount = 2
        let scrobbleTransport = RecordingScrobbleTransport(nowPlaying: nowPlaying)
        let tracker = ScrobbleTracker(
            scrobbleManager: ScrobbleManager(transports: [scrobbleTransport]),
            playbackTransport: mockService
        )
        // Each consumer owns its own subscription to the shared seam.
        tracker.start(consuming: player.playbackTransitions)
        let song = Song(id: "one", title: "One", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        try host.sessionDraft.add([song])

        let session = ListeningSession(songOrder: [song], algorithm: .noRepeat, seed: 1)
        let restored = await player.restore(session, currentSongID: song.id, playbackPosition: 42)
        XCTAssertTrue(restored)
        try await player.play()
        await player.pause()
        try await player.play()
        try await player.startFreshShuffle(seed: 2)
        await fulfillment(of: [nowPlaying], timeout: 2)

        await waitUntil { (try? self.archive.load().session?.seed) == 2 }
        let saved = try archive.load().session
        XCTAssertEqual(saved?.currentSongID, song.id)
        XCTAssertEqual(saved?.seed, 2)
        XCTAssertEqual(saved?.playbackPosition, 0)
        withExtendedLifetime(tracker) {}
    }

    // MARK: - Starting

    func testPlayPauseWithNoSessionShufflesTheDraft() async throws {
        let source = StubAutofillSource(songs: makeSongs("library"))
        let host = makeHost(autofillSource: source, makeSeed: { 7 })
        try host.sessionDraft.add(makeSongs("one", "two"))

        await host.togglePlayback()

        XCTAssertEqual(host.player.activeSession?.seed, 7)
        XCTAssertEqual(Set(host.player.activeSession?.songIDs ?? []), ["one", "two"])
        XCTAssertTrue(host.player.playbackState.isPlaying)
        XCTAssertEqual(source.fetchCount, 0)
    }

    func testPlayPauseWithNoSessionAndAnEmptyDraftAutofillsThenShuffles() async throws {
        let source = StubAutofillSource(songs: makeSongs("a", "b", "c"))
        let host = makeHost(autofillSource: source)

        await host.togglePlayback()

        XCTAssertEqual(Set(host.sessionDraft.songs.map(\.id)), ["a", "b", "c"])
        XCTAssertEqual(Set(host.player.activeSession?.songIDs ?? []), ["a", "b", "c"])
        XCTAssertTrue(host.player.playbackState.isPlaying)
    }

    func testPlayPauseKeepsTheActiveSessionAfterTheDraftIsEmptied() async throws {
        let source = StubAutofillSource(songs: makeSongs("library"))
        let host = makeHost(autofillSource: source)
        try host.sessionDraft.add(makeSongs("one", "two"))
        await host.togglePlayback()
        let session = try XCTUnwrap(host.player.activeSession)
        let current = try XCTUnwrap(host.player.playbackState.currentSong)

        host.sessionDraft.removeAll()
        await host.togglePlayback()
        await waitUntil { host.player.playbackState == .paused(current) }
        await host.togglePlayback()
        await waitUntil { host.player.playbackState == .playing(current) }

        XCTAssertEqual(host.player.activeSession?.id, session.id)
        XCTAssertTrue(host.sessionDraft.isEmpty)
        XCTAssertEqual(source.fetchCount, 0)
    }

    func testStartFreshShuffleReplacesTheActiveSessionButNeverAutofills() async throws {
        let source = StubAutofillSource(songs: makeSongs("library"))
        var seed: UInt64 = 0
        let host = makeHost(autofillSource: source, makeSeed: { seed += 1; return seed })
        try host.sessionDraft.add(makeSongs("one", "two"))

        await host.startFreshShuffle()
        let first = try XCTUnwrap(host.player.activeSession)
        await host.startFreshShuffle()
        let second = try XCTUnwrap(host.player.activeSession)
        XCTAssertNotEqual(second.id, first.id)
        XCTAssertEqual(second.seed, 2)

        host.sessionDraft.removeAll()
        await host.startFreshShuffle()

        XCTAssertEqual(host.player.activeSession?.id, second.id)
        XCTAssertEqual(source.fetchCount, 0)
    }

    func testFreshShuffleAfterTheDraftIsEmptiedCanAutofillToReplaceTheSession() async throws {
        let source = StubAutofillSource(songs: makeSongs("library"))
        let host = makeHost(autofillSource: source)
        try host.sessionDraft.add(makeSongs("one", "two"))
        await host.startFreshShuffle()
        let first = try XCTUnwrap(host.player.activeSession)

        host.sessionDraft.removeAll()
        await host.startFreshShuffle(autofillingEmptyDraft: true)

        XCTAssertEqual(source.fetchCount, 1)
        XCTAssertNotEqual(host.player.activeSession?.id, first.id)
        XCTAssertEqual(host.player.activeSession?.songIDs, ["library"])
    }

    func testIsStartingSessionCoversAutofillAndIgnoresRepeatPresses() async throws {
        let source = StubAutofillSource(songs: makeSongs("a"), holdsUntilReleased: true)
        let host = makeHost(autofillSource: source)

        let start = Task { await host.togglePlayback() }
        await waitUntil { source.isHeld }
        XCTAssertTrue(host.isStartingSession)

        await host.togglePlayback()
        XCTAssertEqual(source.fetchCount, 1)

        source.release()
        await start.value
        XCTAssertFalse(host.isStartingSession)
        XCTAssertEqual(host.player.activeSession?.songIDs, ["a"])
    }

    // MARK: - Warming autofill

    func testEmptyingTheDraftWarmsAutofillButAddingSongsDoesNot() async throws {
        let source = StubAutofillSource(songs: [])
        let host = makeHost(autofillSource: source)

        try host.sessionDraft.add(makeSongs("one", "two"))
        host.sessionDraft.remove(songID: "one")
        await waitForStateUpdate()
        XCTAssertEqual(source.warmCount, 0)

        host.sessionDraft.remove(songID: "two")
        await waitUntil { source.warmCount == 1 }
    }

    func testRestoringAnEmptyPoolWarmsAutofill() async {
        let source = StubAutofillSource(songs: [])
        let host = makeHost(autofillSource: source)

        await host.restoreSavedSession()

        XCTAssertEqual(source.warmCount, 1)
    }

    func testRestoringASavedPoolDoesNotWarmAutofill() async throws {
        try archive.commit(pool: makeSongs("one"), session: nil)
        let source = StubAutofillSource(songs: [])
        let host = makeHost(autofillSource: source)

        await host.restoreSavedSession()
        await waitForStateUpdate()

        XCTAssertEqual(host.sessionDraft.songs.map(\.id), ["one"])
        XCTAssertEqual(source.warmCount, 0)
    }

    // MARK: - Session end

    func testSessionEndContinuesWithAFreshShuffleOfTheStagedDraft() async throws {
        let host = makeHost(makeSeed: { 4 })
        let original = makeSongs("one", "two", "three")
        try host.sessionDraft.add(original)
        await host.startFreshShuffle()
        let ended = try XCTUnwrap(host.player.activeSession)
        try host.sessionDraft.add(makeSongs("added"))
        host.sessionDraft.remove(songID: "one")

        await mockService.simulateSessionEnded()
        await waitUntil {
            host.player.sessionEndCount == 1
                && host.player.activeSession.map { $0.id != ended.id } == true
        }

        XCTAssertEqual(Set(host.player.activeSession?.songIDs ?? []), ["two", "three", "added"])
        XCTAssertTrue(host.player.playbackState.isPlaying)
        let loadCallCount = await mockService.loadCallCount
        XCTAssertEqual(loadCallCount, 2)
    }

    func testSessionEndWithAnEmptyDraftStopsUntilPlayIsPressed() async throws {
        let source = StubAutofillSource(songs: makeSongs("library"))
        let host = makeHost(autofillSource: source)
        try host.sessionDraft.add(makeSongs("one", "two"))
        await host.startFreshShuffle()

        host.sessionDraft.removeAll()
        await mockService.simulateSessionEnded()
        await waitUntil { host.player.sessionEndCount == 1 }
        await waitForStateUpdate()

        XCTAssertNil(host.player.activeSession)
        XCTAssertEqual(host.player.playbackState, .stopped)
        XCTAssertEqual(source.fetchCount, 0)
        let loadsAfterEnd = await mockService.loadCallCount
        XCTAssertEqual(loadsAfterEnd, 1)

        await host.togglePlayback()

        XCTAssertEqual(source.fetchCount, 1)
        XCTAssertEqual(host.player.activeSession?.songIDs, ["library"])
    }

    func testSessionClearNeverStartsANewSession() async throws {
        let host = makeHost()
        try host.sessionDraft.add(makeSongs("one", "two"))
        await host.startFreshShuffle()

        await host.player.clearSession()
        await waitForStateUpdate()

        XCTAssertNil(host.player.activeSession)
        XCTAssertEqual(host.player.playbackState, .empty)
        let loadCallCount = await mockService.loadCallCount
        XCTAssertEqual(loadCallCount, 1)
    }

    func testHostCanBeReleasedWhileWaitingForTransitions() async {
        var host: ListeningSessionHost? = makeHost()
        weak var releasedHost = host
        await Task.yield()
        host = nil
        XCTAssertNil(releasedHost)
    }

    func testCanSkipOnlyWithAnActiveSession() async throws {
        let host = makeHost()
        XCTAssertFalse(host.canSkip)

        try host.sessionDraft.add(makeSongs("one", "two"))
        await host.togglePlayback()

        XCTAssertTrue(host.canSkip)
    }

    func testSkipToNextPlaysTheNextSongInTheSession() async throws {
        let host = makeHost()
        try host.sessionDraft.add(makeSongs("one", "two", "three"))
        await host.togglePlayback()
        let order = try XCTUnwrap(host.player.activeSession?.songIDs)

        await host.skipToNext()

        await waitUntil { host.player.playbackState.currentSongId == order[1] }
        XCTAssertEqual(host.player.playbackState.currentSongId, order[1])
    }

    func testSkipToPreviousRestartsASongThatHasPlayedAWhile() async throws {
        let host = makeHost()
        try host.sessionDraft.add(makeSongs("one", "two"))
        await host.togglePlayback()
        let current = host.player.playbackState.currentSongId
        await mockService.setPlaybackTime(30)

        await host.skipToPrevious()

        XCTAssertEqual(mockService.currentPlaybackTime, 0)
        XCTAssertEqual(host.player.playbackState.currentSongId, current)
    }

    private func makeHost(
        autofillSource: StubAutofillSource? = nil,
        makeSeed: @escaping () -> UInt64 = { 1 },
        now: @escaping () -> Date = Date.init,
        saveAlgorithm: @escaping (ShuffleAlgorithm) -> Void = { _ in },
        lifecyclePersistenceHook: (() -> Void)? = nil
    ) -> ListeningSessionHost {
        let autofillSource = autofillSource ?? StubAutofillSource(songs: [])
        return ListeningSessionHost(
            playbackTransport: mockService,
            archive: archive,
            autofillSource: autofillSource,
            saveAlgorithm: saveAlgorithm,
            makeSeed: makeSeed,
            now: now,
            lifecyclePersistenceHook: lifecyclePersistenceHook
        )
    }

    private func makeSongs(_ ids: String...) -> [Song] {
        ids.map { Song(id: $0, title: $0, artist: "Artist", albumTitle: "Album", artworkURL: nil) }
    }
}

/// Serves fixed songs, optionally holding each fetch until released so a test
/// can observe the host mid-autofill.
@MainActor
private final class StubAutofillSource: WarmableAutofillSource {
    private let songs: [Song]
    private let holdsUntilReleased: Bool
    private var held: CheckedContinuation<Void, Never>?
    private(set) var fetchCount = 0
    private(set) var warmCount = 0

    var isHeld: Bool { held != nil }

    init(songs: [Song], holdsUntilReleased: Bool = false) {
        self.songs = songs
        self.holdsUntilReleased = holdsUntilReleased
    }

    func warm() {
        warmCount += 1
    }

    func release() {
        held?.resume()
        held = nil
    }

    func fetchSongs(excluding: Set<String>, limit: Int) async throws -> [Song] {
        fetchCount += 1
        if holdsUntilReleased {
            await withCheckedContinuation { held = $0 }
        }
        return Array(songs.filter { !excluding.contains($0.id) }.prefix(limit))
    }
}

private actor RecordingScrobbleTransport: ScrobbleTransport {
    let isAuthenticated = true
    private let nowPlaying: XCTestExpectation

    init(nowPlaying: XCTestExpectation) {
        self.nowPlaying = nowPlaying
    }

    func sendNowPlaying(_ event: ScrobbleEvent) async {
        nowPlaying.fulfill()
    }

    func scrobble(_ event: ScrobbleEvent) async {}
}
