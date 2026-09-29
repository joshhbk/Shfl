import XCTest
@testable import Shfl

/// The MusicKit transport adapter against a fake player that reproduces
/// MusicKit's quirks. Timing of the end-of-session confirmation is controlled
/// by the test.
@MainActor
final class MusicKitTransportTests: XCTestCase {
    private var fake: FakeMusicPlayer!
    private var delay: ManualDelay!
    private var transport: MusicKitTransport!
    private var events: [PlaybackEvent] = []
    private var eventTask: Task<Void, Never>?

    private let songs = ["one", "two", "three"].map {
        Song(id: "i.\($0)", title: $0, artist: "Artist", albumTitle: "Album", artworkURL: nil)
    }

    override func setUp() async throws {
        fake = FakeMusicPlayer()
        delay = ManualDelay()
        let delay = delay!
        transport = MusicKitTransport(player: fake, confirmationDelay: { await delay.wait() })
        let stream = transport.playbackEvents
        eventTask = Task { @MainActor [weak self] in
            for await event in stream {
                self?.events.append(event)
            }
        }
        await waitForStateUpdate()
        events = []
    }

    override func tearDown() async throws {
        delay.releaseAll()
        eventTask?.cancel()
        transport = nil
        fake = nil
        delay = nil
    }

    func testReportsSessionSongsAfterMusicKitReplacesIdentifiers() async throws {
        try await transport.load(request(currentSongID: songs[0].id))
        await waitForStateUpdate()

        XCTAssertEqual(fake.currentEntry?.song?.id, "catalog-i.one")
        XCTAssertEqual(transport.currentSongId, songs[0].id)
        XCTAssertEqual(events.last, .stateChanged(.playing(songs[0])))
    }

    func testDropsSongsThatNoLongerResolve() async throws {
        fake.unresolvableSongIDs = [songs[1].id]
        try await transport.load(request(currentSongID: songs[0].id))

        try await transport.skipToNext()
        await waitForStateUpdate()

        XCTAssertEqual(transport.currentSongId, songs[2].id)
        XCTAssertEqual(events.last, .stateChanged(.playing(songs[2])))
    }

    func testMovingBetweenSongsDoesNotPublishEmptyOrStopped() async throws {
        try await transport.load(request(currentSongID: songs[0].id))
        try await transport.skipToNext()
        await waitForStateUpdate()

        XCTAssertFalse(events.contains(.stateChanged(.empty)))
        XCTAssertFalse(events.contains(.stateChanged(.stopped)))
        XCTAssertEqual(events.last, .stateChanged(.playing(songs[1])))
    }

    func testLoadWithoutAutoplayReportsPausedSong() async throws {
        try await transport.load(request(currentSongID: songs[1].id, autoplay: false))
        await waitForStateUpdate()

        XCTAssertEqual(events.last, .stateChanged(.paused(songs[1])))
    }

    func testFinalSongEndsSessionOnceAfterConfirmation() async throws {
        try await transport.load(request(currentSongID: songs[2].id))
        await fake.finishCurrentEntry()
        await waitForStateUpdate()

        XCTAssertFalse(events.contains(.sessionEnded))
        XCTAssertEqual(delay.pendingCount, 1)

        delay.releaseAll()
        await waitForStateUpdate()
        await fake.finishCurrentEntry()
        delay.releaseAll()
        await waitForStateUpdate()

        XCTAssertEqual(events.filter { $0 == .sessionEnded }.count, 1)
    }

    func testStopThatRecoversOnFinalSongDoesNotEndSession() async throws {
        // A stop with the entry still loaded surfaces as paused; it only ends
        // the session if it lasts through the confirmation delay.
        try await transport.load(request(currentSongID: songs[2].id))
        await fake.stutter()
        await waitForStateUpdate()

        delay.releaseAll()
        await waitForStateUpdate()

        XCTAssertFalse(events.contains(.sessionEnded))
        XCTAssertEqual(events.last, .stateChanged(.playing(songs[2])))
    }

    func testFinalSongNeverPlayedDoesNotEndSession() async throws {
        try await transport.load(request(currentSongID: songs[2].id, autoplay: false))
        await waitForStateUpdate()

        XCTAssertEqual(delay.pendingCount, 0)
        XCTAssertFalse(events.contains(.sessionEnded))
    }

    func testClearPublishesEmpty() async throws {
        try await transport.load(request(currentSongID: songs[0].id))
        await transport.clear()
        await waitForStateUpdate()

        XCTAssertEqual(events.last, .stateChanged(.empty))
        XCTAssertNil(transport.currentSongId)
    }

    func testRestartOrSkipToPreviousRestartsPastThreeSeconds() async throws {
        try await transport.load(request(currentSongID: songs[1].id))
        transport.seek(to: 30)

        try await transport.restartOrSkipToPrevious()
        XCTAssertEqual(transport.currentPlaybackTime, 0)
        XCTAssertEqual(transport.currentSongId, songs[1].id)

        try await transport.restartOrSkipToPrevious()
        await waitForStateUpdate()
        XCTAssertEqual(transport.currentSongId, songs[0].id)
    }

    private func request(currentSongID: String, autoplay: Bool = true) -> PlaybackLoadRequest {
        PlaybackLoadRequest(
            sessionID: UUID(),
            queue: songs,
            currentSongID: currentSongID,
            playbackPosition: 0,
            autoplay: autoplay
        )
    }
}
