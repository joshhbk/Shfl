import XCTest
@testable import Shfl

@MainActor
final class PlaybackTransitionTests: XCTestCase {
    func test_subscribersReceiveEveryEdgeInOrderWithoutDuplicateLoadReports() async throws {
        let transport = DeterministicMusicService()
        let player = ShufflePlayer(playbackTransport: transport)
        let song = makeSong("one")
        try player.seedSongs([song])
        let first = player.playbackTransitions
        let second = player.playbackTransitions

        try await player.startFreshShuffle(seed: 1)
        await player.pause()
        try await player.play()
        await player.pause()

        for stream in [first, second] {
            let transitions = await collect(stream, count: 5)
            XCTAssertEqual(transitions.map(\.state), [.empty, .playing(song), .paused(song), .playing(song), .paused(song)])
            XCTAssertEqual(transitions.map(\.startsSong), [false, true, false, false, false])
            XCTAssertEqual(transitions.map(\.songChanged), [false, true, false, false, false])
        }
    }

    func test_restoreThenPlayStartsSongOnceAndFreshSessionStartsItAgain() async throws {
        let transport = DeterministicMusicService()
        let player = ShufflePlayer(playbackTransport: transport)
        let song = makeSong("one")
        try player.seedSongs([song])
        let stream = player.playbackTransitions
        let restored = await player.restoreSession(
            queueOrder: [song.id], currentSongId: song.id,
            playedIds: [], playbackPosition: 42, seed: 1
        )
        XCTAssertTrue(restored)
        // Wait for the restored state through the real seam before resuming.
        let restoredEvents = await collect(stream, count: 2)
        XCTAssertEqual(restoredEvents.last?.state, .paused(song))
        XCTAssertEqual(restoredEvents.last?.playbackTime, 42)
        XCTAssertEqual(restoredEvents.last?.startsSong, false)

        let resumed = player.playbackTransitions
        try await player.play()
        let resumedEvents = await collect(resumed, count: 2)
        XCTAssertEqual(resumedEvents.last?.startsSong, true)
        let oldSession = player.activeSession?.id

        let fresh = player.playbackTransitions
        try await player.startFreshShuffle(seed: 2)
        let freshEvents = await collect(fresh, count: 2)
        XCTAssertEqual(freshEvents.last?.startsSong, true)
        XCTAssertEqual(freshEvents.last?.songChanged, true)
        XCTAssertNotEqual(freshEvents.last?.session?.id, oldSession)
    }

    func test_loadingNewSongThenPlayingDetectsStartAfterSongChange() async throws {
        let transport = DeterministicMusicService()
        let player = ShufflePlayer(playbackTransport: transport)
        let song = makeSong("one")
        try player.seedSongs([song])
        try await player.startFreshShuffle(seed: 1)
        let stream = player.playbackTransitions
        let next = makeSong("two")
        await transport.simulatePlaybackState(.loading(next))
        await transport.simulatePlaybackState(.playing(next))
        await transport.simulatePlaybackState(.playing(next))
        await transport.simulatePlaybackState(.paused(next))
        let events = await collect(stream, count: 4)
        XCTAssertEqual(events.map(\.state), [.playing(song), .loading(next), .playing(next), .paused(next)])
        XCTAssertEqual(events.map(\.startsSong), [true, false, true, false])
        XCTAssertEqual(events.map(\.songChanged), [true, true, false, false])
    }

    func test_transientEmptyIsSuppressedAndClearPublishesEmpty() async throws {
        let transport = DeterministicMusicService()
        let player = ShufflePlayer(playbackTransport: transport)
        let song = makeSong("one")
        try player.seedSongs([song])
        try await player.startFreshShuffle(seed: 1)
        let stream = player.playbackTransitions
        await transport.simulatePlaybackState(.empty)
        await transport.simulatePlaybackState(.paused(song))
        let events = await collect(stream, count: 2)
        XCTAssertEqual(events.map(\.state), [.playing(song), .paused(song)])

        let cleared = player.playbackTransitions
        await player.removeAllSongs()
        let clearEvents = await collect(cleared, count: 2)
        XCTAssertEqual(clearEvents.last?.state, .empty)
        XCTAssertNil(clearEvents.last?.session)
    }

    func test_sessionExhaustionPublishesStopThenOneFreshSession() async throws {
        let transport = DeterministicMusicService()
        let player = ShufflePlayer(playbackTransport: transport)
        let song = makeSong("one")
        try player.seedSongs([song])
        try await player.startFreshShuffle(seed: 1)
        let oldSession = player.activeSession?.id
        let stream = player.playbackTransitions
        await transport.simulateSessionEnded()
        let events = await collect(stream, count: 3)
        XCTAssertEqual(events.map(\.state), [.playing(song), .stopped, .playing(song)])
        XCTAssertNil(events[1].session)
        XCTAssertNotEqual(events.last?.session?.id, oldSession)
        XCTAssertEqual(events.last?.startsSong, true)
        let loads = await transport.loadCallCount
        XCTAssertEqual(loads, 2)
    }

    func test_failedLoadPublishesFailureWithoutACommittedSession() async throws {
        let transport = DeterministicMusicService()
        let player = ShufflePlayer(playbackTransport: transport)
        try player.seedSongs([makeSong("one")])
        let stream = player.playbackTransitions
        await transport.failNextLoad(with: NSError(domain: "load", code: 1))
        do {
            try await player.startFreshShuffle(seed: 1)
            XCTFail("Expected failure")
        } catch {}
        let events = await collect(stream, count: 2)
        guard case .error = events.last?.state else {
            return XCTFail("Expected an error transition")
        }
        XCTAssertNil(events.last?.session)
        XCTAssertFalse(events.contains(where: \.startsSong))
    }

    func test_cancellingOneSubscriberDoesNotStopAnother() async throws {
        let transport = DeterministicMusicService()
        let player = ShufflePlayer(playbackTransport: transport)
        let song = makeSong("one")
        try player.seedSongs([song])
        let cancelledStream = player.playbackTransitions
        let task = Task { for await _ in cancelledStream {} }
        await Task.yield()
        task.cancel()
        await task.value
        let remaining = player.playbackTransitions
        try await player.startFreshShuffle(seed: 1)
        let events = await collect(remaining, count: 2)
        XCTAssertEqual(events.map(\.state), [.empty, .playing(song)])
    }

    func test_streamFinishesWhenPlayerIsReleased() async {
        let transport = DeterministicMusicService()
        var player: ShufflePlayer? = ShufflePlayer(playbackTransport: transport)
        weak var weakPlayer = player
        let stream = player!.playbackTransitions
        // Let the transport observation task reach its suspension point.
        await Task.yield()
        player = nil
        XCTAssertNil(weakPlayer)
        let finished = expectation(description: "Stream finished")
        let task = Task {
            for await _ in stream {}
            finished.fulfill()
        }
        await fulfillment(of: [finished], timeout: 2)
        task.cancel()
    }

    private func collect(_ stream: AsyncStream<PlaybackTransition>, count: Int) async -> [PlaybackTransition] {
        let received = expectation(description: "Received \(count) transitions")
        var result: [PlaybackTransition] = []
        let task = Task {
            for await transition in stream {
                result.append(transition)
                if result.count == count {
                    received.fulfill()
                    return
                }
            }
        }
        await fulfillment(of: [received], timeout: 2)
        task.cancel()
        return result
    }

    private func makeSong(_ id: String) -> Song {
        Song(id: id, title: id, artist: "Artist", albumTitle: "Album", artworkURL: nil)
    }
}
