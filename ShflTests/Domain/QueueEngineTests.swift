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
            shouldReconcile: true,
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
            shouldReconcile: true,
            pendingSeekConsumed: nil
        )

        let reduction = try QueueEngineReducer.reduce(state: state, intent: .playbackResolution(resolution))
        XCTAssertTrue(
            reduction.nextState.queueNeedsBuild,
            "Terminal playing->stopped transitions should require a fresh queue build"
        )
    }
}
