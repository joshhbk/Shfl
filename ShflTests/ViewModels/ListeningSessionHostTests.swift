import SwiftData
import UIKit
import XCTest
@testable import Shfl

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

    func testHandleDidEnterBackgroundCheckpointsSession() async throws {
        let host = makeHost()
        let player = host.player

        let song = Song(
            id: "1",
            title: "Song 1",
            artist: "Artist 1",
            albumTitle: "Album 1",
            artworkURL: nil
        )

        try await player.addSong(song)
        try await player.startFreshShuffle(seed: 5)
        await waitUntil { (try? self.archive.load().session) != nil }

        await mockService.setPlaybackTime(42)
        host.handleDidEnterBackground()

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

        try host.player.seedSongs(songs)
        await waitUntil { (try? self.archive.load().pool.map(\.id)) == ["one", "two"] }

        // A swipe-dismissed sheet never reports back; the edit alone must be durable.
        await host.player.removeSong(id: "one")
        await waitUntil { (try? self.archive.load().pool.map(\.id)) == ["two"] }
    }

    func testFreshShuffleAndDraftEditRestoreOnNextLaunch() async throws {
        let song = Song(id: "one", title: "One", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        let host = makeHost()

        // Same ordering as AppViewModel.shuffleAll: seed then start, no yield between.
        try host.player.seedSongs([song])
        try await host.player.startFreshShuffle(seed: 7)
        await waitUntil { (try? self.archive.load().session?.seed) == 7 }
        await waitForStateUpdate()

        let nextTransport = DeterministicMusicService()
        let nextHost = ListeningSessionHost(
            playbackTransport: nextTransport,
            archive: SessionArchive(modelContext: ModelContext(container))
        )
        let restored = await nextHost.restoreSavedSession()
        XCTAssertTrue(restored)
        XCTAssertEqual(nextHost.player.allSongs, [song])
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

        try await host.player.addSong(added)
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
        XCTAssertEqual(host.player.allSongs, [song])
        let saved = try archive.load()
        XCTAssertEqual(saved.pool, [song])
        XCTAssertNil(saved.session)
    }

    func testRemoveAllThenCheckpointDoesNotReviveSession() async throws {
        let song = Song(id: "one", title: "One", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        let host = makeHost()
        try host.player.seedSongs([song])
        try await host.player.startFreshShuffle(seed: 7)
        await waitUntil { (try? self.archive.load().session) != nil }

        await host.player.removeAllSongs()
        await waitUntil { (try? self.archive.load().session) == nil }
        await waitForStateUpdate()
        host.handleDidEnterBackground()
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
        try player.seedSongs(songs)
        try await player.startFreshShuffle(seed: 7)
        await waitUntil { (try? self.archive.load().session) != nil }
        let previousID = try XCTUnwrap(archive.load().session?.currentSongID)
        let selectedID = try XCTUnwrap(songs.first { $0.id != previousID }?.id)
        let session = try XCTUnwrap(player.activeSession)
        let restored = await player.restore(session, currentSongID: selectedID, playbackPosition: 23)
        XCTAssertTrue(restored)
        host.handleDidEnterBackground()
        let saved = try archive.load()
        XCTAssertEqual(saved.session?.currentSongID, selectedID)
        XCTAssertEqual(saved.session?.playbackPosition, 23)
    }

    func testUnrecognizedTransportSongDoesNotEraseLastValidSession() async throws {
        let librarySong = Song(id: "i.library", title: "Song", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        let catalogSong = Song(id: "123456", title: "Song", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        let host = makeHost()
        let player = host.player
        try player.seedSongs([librarySong])
        try await player.startFreshShuffle(seed: 7)
        await waitUntil { (try? self.archive.load().session) != nil }
        let validRecord = try XCTUnwrap(archive.load().session)

        // MusicKit can surface the catalog representation of a library song.
        // An unrecognized report must not be interpreted as an explicit clear.
        await mockService.simulatePlaybackState(.playing(catalogSong))
        await waitUntil { player.playbackState.currentSongId == catalogSong.id }
        host.handleDidEnterBackground()
        XCTAssertEqual(try archive.load().session, validRecord)
    }

    func testDidEnterBackgroundNotificationTriggersSinglePersistenceCall() async throws {
        var persistCallCount = 0
        let host = makeHost(lifecyclePersistenceHook: { persistCallCount += 1 })

        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)

        for _ in 0..<10 {
            if persistCallCount == 1 { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        XCTAssertEqual(persistCallCount, 1)
        withExtendedLifetime(host) {}
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
        try player.seedSongs([song])

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

    func testHostCanBeReleasedWhileWaitingForTransitions() async {
        var host: ListeningSessionHost? = makeHost()
        weak var releasedHost = host
        await Task.yield()
        host = nil
        XCTAssertNil(releasedHost)
    }

    private func makeHost(
        now: @escaping () -> Date = Date.init,
        lifecyclePersistenceHook: (() -> Void)? = nil
    ) -> ListeningSessionHost {
        ListeningSessionHost(
            playbackTransport: mockService,
            archive: archive,
            now: now,
            lifecyclePersistenceHook: lifecyclePersistenceHook
        )
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
