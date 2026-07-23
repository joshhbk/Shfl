import XCTest
@testable import Shfl

@MainActor
final class ShufflePlayerTests: XCTestCase {
    func test_firstPlayLoadsOneExactSessionAtBeginning() async throws {
        let transport = DeterministicMusicService()
        let player = ShufflePlayer(playbackTransport: transport)
        let songs = makeSongs(5)
        try player.seedSongs(songs)

        try await player.startFreshShuffle(algorithm: .noRepeat, seed: 42)

        let request = await transport.lastLoadRequest
        let loadCallCount = await transport.loadCallCount
        XCTAssertEqual(loadCallCount, 1)
        XCTAssertEqual(request?.queue.map(\.id), player.activeSession?.songIDs)
        XCTAssertEqual(request?.currentSongID, player.activeSession?.songIDs.first)
        XCTAssertEqual(request?.playbackPosition, 0)
        XCTAssertEqual(request?.autoplay, true)
    }

    func test_sameSeedProducesSameOrder() throws {
        let draft = SessionDraft(songs: makeSongs(12), algorithm: .noRepeat)
        let composer = SessionComposer()

        let first = try composer.compose(draft: draft, seed: 123)
        let second = try composer.compose(draft: draft, seed: 123)

        XCTAssertEqual(first.songIDs, second.songIDs)
    }

    func test_activeEditsOnlyChangeNextSessionDraft() async throws {
        let transport = DeterministicMusicService()
        let player = ShufflePlayer(playbackTransport: transport)
        let original = makeSongs(4)
        try player.seedSongs(original)
        try await player.startFreshShuffle(seed: 7)
        let activeOrder = try XCTUnwrap(player.activeSession?.songIDs)

        let addition = Song(
            id: "new",
            title: "New",
            artist: "Artist",
            albumTitle: "",
            artworkURL: nil
        )
        try await player.addSong(addition)
        await player.removeSong(id: original[0].id)

        let loadCallCount = await transport.loadCallCount
        XCTAssertEqual(loadCallCount, 1)
        XCTAssertEqual(player.activeSession?.songIDs, activeOrder)
        XCTAssertTrue(player.hasPendingSessionChanges)
        XCTAssertTrue(player.allSongs.contains(addition))
        XCTAssertFalse(player.allSongs.contains(original[0]))
    }

    func test_algorithmChangeDoesNotReloadActiveSession() async throws {
        let transport = DeterministicMusicService()
        let player = ShufflePlayer(playbackTransport: transport)
        try player.seedSongs(makeSongs(5))
        try await player.startFreshShuffle(algorithm: .noRepeat, seed: 1)

        player.stageAlgorithm(.artistSpacing)

        let loadCallCount = await transport.loadCallCount
        XCTAssertEqual(loadCallCount, 1)
        XCTAssertEqual(player.activeSession?.algorithm, .noRepeat)
        XCTAssertEqual(player.draft.algorithm, .artistSpacing)
        XCTAssertTrue(player.hasPendingSessionChanges)
    }

    func test_pauseAndResumePreserveSessionPositionWithoutReload() async throws {
        let transport = DeterministicMusicService()
        let player = ShufflePlayer(playbackTransport: transport)
        try player.seedSongs(makeSongs(3))
        try await player.startFreshShuffle(seed: 6)
        let sessionID = player.activeSession?.id
        await transport.setPlaybackTime(42)

        await player.pause()
        try await player.play()
        await settle()

        XCTAssertEqual(player.activeSession?.id, sessionID)
        XCTAssertEqual(transport.currentPlaybackTime, 42)
        let loadCallCount = await transport.loadCallCount
        XCTAssertEqual(loadCallCount, 1)
    }

    func test_nextAndPreviousFollowSessionOrderWithoutReload() async throws {
        let transport = DeterministicMusicService()
        let player = ShufflePlayer(playbackTransport: transport)
        try player.seedSongs(makeSongs(4))
        try await player.startFreshShuffle(seed: 11)
        let order = try XCTUnwrap(player.activeSession?.songIDs)

        try await player.skipToNext()
        await waitUntil { player.playbackState.currentSongId == order[1] }
        await transport.setPlaybackTime(0)
        try await player.restartOrSkipToPrevious()
        await waitUntil { player.playbackState.currentSongId == order[0] }

        let loadCallCount = await transport.loadCallCount
        XCTAssertEqual(loadCallCount, 1)
    }

    func test_virtualTimeAdvancesFiveSongsWithoutReloadingOrWrapping() async throws {
        let transport = DeterministicMusicService()
        let player = ShufflePlayer(playbackTransport: transport)
        try player.seedSongs(makeSongs(5))
        try await player.startFreshShuffle(seed: 99)
        await settle()

        await transport.advance(by: 4 * 180 + 10)
        await waitUntil {
            player.playbackState.currentSongId == player.activeSession?.songIDs.last
        }

        XCTAssertEqual(player.playbackState.currentSongId, player.activeSession?.songIDs.last)
        let loadCallCountBeforeEnd = await transport.loadCallCount
        XCTAssertEqual(loadCallCountBeforeEnd, 1)

        await transport.advance(by: 180)
        await waitUntil {
            player.sessionEndCount == 1 && player.activeSession != nil
        }

        XCTAssertNotNil(player.activeSession)
        XCTAssertTrue(player.playbackState.isPlaying)
        XCTAssertEqual(player.sessionEndCount, 1)
        let loadCallCountAfterEnd = await transport.loadCallCount
        XCTAssertEqual(loadCallCountAfterEnd, 2)
    }

    func test_transientEmptyDoesNotEndOrReloadSession() async throws {
        let transport = DeterministicMusicService()
        let player = ShufflePlayer(playbackTransport: transport)
        try player.seedSongs(makeSongs(3))
        try await player.startFreshShuffle(seed: 4)
        let activeID = player.activeSession?.id
        await settle()

        await transport.simulatePlaybackState(.empty)
        await settle()

        XCTAssertEqual(player.activeSession?.id, activeID)
        XCTAssertEqual(player.sessionEndCount, 0)
        let loadCallCount = await transport.loadCallCount
        XCTAssertEqual(loadCallCount, 1)
    }

    func test_sessionEndBuildsNextSessionFromStagedDraft() async throws {
        let transport = DeterministicMusicService()
        let player = ShufflePlayer(playbackTransport: transport)
        let original = makeSongs(3)
        let added = Song(
            id: "added",
            title: "Added",
            artist: "New Artist",
            albumTitle: "Album",
            artworkURL: nil
        )
        try player.seedSongs(original)
        try await player.startFreshShuffle(seed: 4)
        try await player.addSong(added)
        await player.removeSong(id: original[0].id)
        await settle()

        await transport.simulateSessionEnded()
        await waitUntil {
            player.sessionEndCount == 1 && player.activeSession != nil
        }

        XCTAssertEqual(
            Set(player.activeSession?.songIDs ?? []),
            Set([original[1].id, original[2].id, added.id])
        )
        let loadCallCount = await transport.loadCallCount
        XCTAssertEqual(loadCallCount, 2)
    }

    func test_restoreUsesOnePausedAtomicLoadWithExactOrderAndPosition() async throws {
        let transport = DeterministicMusicService()
        let player = ShufflePlayer(playbackTransport: transport)
        let songs = makeSongs(4)
        try player.seedSongs(songs)
        let order = [songs[2].id, songs[0].id, songs[3].id, songs[1].id]

        let restored = await player.restoreSession(
            queueOrder: order,
            currentSongId: songs[3].id,
            playedIds: [songs[2].id, songs[0].id],
            playbackPosition: 61,
            algorithm: .artistSpacing,
            seed: 88
        )

        let request = await transport.lastLoadRequest
        XCTAssertTrue(restored)
        XCTAssertEqual(request?.queue.map(\.id), order)
        XCTAssertEqual(request?.currentSongID, songs[3].id)
        XCTAssertEqual(request?.playbackPosition, 61)
        XCTAssertEqual(request?.autoplay, false)
        let loadCallCount = await transport.loadCallCount
        XCTAssertEqual(loadCallCount, 1)
    }

    func test_clearIsTheOnlyDraftEditThatClearsActiveSession() async throws {
        let transport = DeterministicMusicService()
        let player = ShufflePlayer(playbackTransport: transport)
        try player.seedSongs(makeSongs(3))
        try await player.startFreshShuffle(seed: 2)

        await player.removeAllSongs()
        await settle()

        XCTAssertTrue(player.draftIsEmpty)
        XCTAssertNil(player.activeSession)
        XCTAssertEqual(player.playbackState, .empty)
    }

    func test_failedFreshLoadLeavesNoFalseActiveSession() async throws {
        let transport = DeterministicMusicService()
        let player = ShufflePlayer(playbackTransport: transport)
        try player.seedSongs(makeSongs(3))
        await transport.failNextLoad(with:
            NSError(domain: "test-load", code: 1)
        )

        do {
            try await player.startFreshShuffle(seed: 2)
            XCTFail("Expected the load to fail")
        } catch {
            XCTAssertNil(player.activeSession)
            XCTAssertFalse(player.playbackState.isActive)
            XCTAssertNotNil(player.operationNotice)
        }
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

    private func settle() async {
        for _ in 0..<5 {
            await Task.yield()
        }
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        for _ in 0..<500 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("Timed out waiting for deterministic playback event")
    }
}
