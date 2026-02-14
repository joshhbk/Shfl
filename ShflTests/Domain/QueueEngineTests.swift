import XCTest
@testable import Shfl

final class QueueEngineTests: XCTestCase {
    func testPlaybackResolutionLoadingToStoppedKeepsQueueBuildValid() throws {
        let song = Song(id: "1", title: "Song 1", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        let queueState = QueueState(songPool: [song], queueOrder: [song], currentIndex: 0)
        let state = QueueEngineState(
            queueState: queueState,
            playbackState: .loading(song),
            revision: 4,
            queueNeedsBuild: false
        )
        let resolution = PlaybackStateResolution(
            resolvedState: .stopped,
            resolvedSongId: song.id,
            shouldUpdateCurrentSong: true,
            songIdToMarkPlayed: nil,
            shouldClearHistory: true,
            pendingSeekConsumed: nil
        )

        let reduction = try QueueEngineReducer.reduce(state: state, intent: .playbackResolution(resolution))
        XCTAssertFalse(
            reduction.nextState.queueNeedsBuild,
            "Transient loading->stopped during queue startup should not force an immediate rebuild"
        )
    }

    func testPlaybackResolutionPlayingToStoppedMarksQueueNeedsBuild() throws {
        let song = Song(id: "1", title: "Song 1", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        let queueState = QueueState(songPool: [song], queueOrder: [song], currentIndex: 0)
        let state = QueueEngineState(
            queueState: queueState,
            playbackState: .playing(song),
            revision: 10,
            queueNeedsBuild: false
        )
        let resolution = PlaybackStateResolution(
            resolvedState: .stopped,
            resolvedSongId: song.id,
            shouldUpdateCurrentSong: true,
            songIdToMarkPlayed: nil,
            shouldClearHistory: true,
            pendingSeekConsumed: nil
        )

        let reduction = try QueueEngineReducer.reduce(state: state, intent: .playbackResolution(resolution))
        XCTAssertTrue(
            reduction.nextState.queueNeedsBuild,
            "Terminal playing->stopped transitions should require a fresh queue build"
        )
    }

    func testRemoveAllSongsClearsQueueWithoutPendingBuild() throws {
        let song = Song(id: "1", title: "Song 1", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        let queueState = QueueState(songPool: [song], queueOrder: [song], currentIndex: 0)
        let state = QueueEngineState(
            queueState: queueState,
            playbackState: .paused(song),
            revision: 7,
            queueNeedsBuild: true
        )

        let reduction = try QueueEngineReducer.reduce(state: state, intent: .removeAllSongs)
        XCTAssertEqual(reduction.nextState.queueState, .empty)
        XCTAssertEqual(reduction.nextState.playbackState, .empty)
        XCTAssertFalse(reduction.nextState.queueNeedsBuild, "Empty state should not signal pending queue build")
    }

    func testAddSongDuringActivePlaybackPreservesCurrentIndexOnAppend() throws {
        let song1 = Song(id: "1", title: "Song 1", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        let song2 = Song(id: "2", title: "Song 2", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        let song3 = Song(id: "3", title: "Song 3", artist: "Artist", albumTitle: "Album", artworkURL: nil)

        let queueState = QueueState(songPool: [song1, song2], queueOrder: [song1, song2], currentIndex: 1)
        let state = QueueEngineState(
            queueState: queueState,
            playbackState: .playing(song2),
            revision: 2,
            queueNeedsBuild: false
        )

        let reduction = try QueueEngineReducer.reduce(state: state, intent: .addSong(song3))
        XCTAssertEqual(reduction.nextState.queueState.currentSongId, song2.id)
        XCTAssertEqual(reduction.nextState.queueState.currentIndex, 1)
        XCTAssertEqual(reduction.nextState.queueState.queueOrder.last?.id, song3.id)
        XCTAssertFalse(reduction.nextState.queueNeedsBuild)

        guard case .insertIntoQueue(let songs, _) = reduction.transportCommands.first else {
            return XCTFail("Expected insertIntoQueue command for active append")
        }
        XCTAssertEqual(songs.map(\.id), [song3.id])
    }

    func testAddSongDuringActivePlaybackRebuildsImmediatelyWhenCurrentSongIsNotInQueue() throws {
        let song1 = Song(id: "1", title: "Song 1", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        let song2 = Song(id: "2", title: "Song 2", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        let song3 = Song(id: "3", title: "Song 3", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        let ghostCurrent = Song(id: "ghost", title: "Ghost", artist: "Artist", albumTitle: "Album", artworkURL: nil)

        let queueState = QueueState(songPool: [song1, song2], queueOrder: [song1, song2], currentIndex: 0)
        let state = QueueEngineState(
            queueState: queueState,
            playbackState: .playing(ghostCurrent),
            revision: 5,
            queueNeedsBuild: true
        )

        let reduction = try QueueEngineReducer.reduce(state: state, intent: .addSong(song3))
        XCTAssertFalse(reduction.nextState.queueNeedsBuild, "Active add should rebuild now, not defer")
        XCTAssertEqual(Set(reduction.nextState.queueState.queueOrder.map(\.id)), Set([song1.id, song2.id, song3.id]))

        guard case .replaceQueue(let queue, let startAtSongId, _, _) = reduction.transportCommands.first else {
            return XCTFail("Expected replaceQueue command for stale active add")
        }
        XCTAssertEqual(Set(queue.map(\.id)), Set([song1.id, song2.id, song3.id]))
        XCTAssertNotNil(startAtSongId, "Rebuild should choose a valid current anchor")
    }
}
