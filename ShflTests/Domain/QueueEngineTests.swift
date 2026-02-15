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

    func testPlaybackResolutionPlayingToStoppedDoesNotForceQueueRebuild() throws {
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
        XCTAssertFalse(
            reduction.nextState.queueNeedsBuild,
            "Stop transitions should not force queue rebuild without explicit corruption/error signals"
        )
    }

    func testPlaybackResolutionErrorMarksQueueNeedsBuild() throws {
        let song = Song(id: "1", title: "Song 1", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        let queueState = QueueState(songPool: [song], queueOrder: [song], currentIndex: 0)
        let state = QueueEngineState(
            queueState: queueState,
            playbackState: .playing(song),
            revision: 10,
            queueNeedsBuild: false
        )
        let resolution = PlaybackStateResolution(
            resolvedState: .error(NSError(domain: "test", code: 55)),
            resolvedSongId: song.id,
            shouldUpdateCurrentSong: true,
            songIdToMarkPlayed: nil,
            shouldClearHistory: true,
            pendingSeekConsumed: nil
        )

        let reduction = try QueueEngineReducer.reduce(state: state, intent: .playbackResolution(resolution))
        XCTAssertTrue(
            reduction.nextState.queueNeedsBuild,
            "Explicit playback errors should force queue rebuild on next play"
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

    func testAddSongDuringActivePlaybackRebuildsUpcomingAndPreservesCurrentAnchor() throws {
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
        XCTAssertEqual(reduction.nextState.queueState.currentIndex, 0)
        XCTAssertTrue(reduction.nextState.queueState.queueOrder.contains(where: { $0.id == song3.id }))
        XCTAssertTrue(
            reduction.nextState.queueNeedsBuild,
            "Active add should defer transport sync to avoid playback interruption"
        )
        XCTAssertEqual(
            Set(reduction.nextState.queueState.queueOrder.map(\.id)),
            Set([song1.id, song2.id, song3.id]),
            "Active add should keep queue membership canonical after upcoming reshuffle"
        )
        XCTAssertTrue(
            reduction.transportCommands.isEmpty,
            "Active add should not emit transport commands to avoid playback pause"
        )
    }

    func testAddSongDuringActivePlaybackDefersTransportEvenWhenQueueNeedsBuildIsSet() throws {
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
        XCTAssertTrue(
            reduction.nextState.queueNeedsBuild,
            "Active add should defer transport sync to avoid playback interruption"
        )
        XCTAssertEqual(Set(reduction.nextState.queueState.queueOrder.map(\.id)), Set([song1.id, song2.id, song3.id]))
        XCTAssertTrue(
            reduction.transportCommands.isEmpty,
            "Active add should not emit transport commands to avoid playback pause"
        )
    }

    func testAddSongsWithRebuildDuringActivePlaybackDefersTransportWhenPlaybackSongMissing() throws {
        let song1 = Song(id: "1", title: "Song 1", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        let song2 = Song(id: "2", title: "Song 2", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        let newSongs = [
            Song(id: "3", title: "Song 3", artist: "Artist", albumTitle: "Album", artworkURL: nil),
            Song(id: "4", title: "Song 4", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        ]
        let ghostCurrent = Song(id: "ghost", title: "Ghost", artist: "Artist", albumTitle: "Album", artworkURL: nil)

        let queueState = QueueState(songPool: [song1, song2], queueOrder: [song1, song2], currentIndex: 1)
        let state = QueueEngineState(
            queueState: queueState,
            playbackState: .paused(ghostCurrent),
            revision: 9,
            queueNeedsBuild: true
        )

        let reduction = try QueueEngineReducer.reduce(state: state, intent: .addSongsWithRebuild(newSongs, algorithm: nil))
        XCTAssertTrue(
            reduction.nextState.queueNeedsBuild,
            "Active batch add should defer transport sync to avoid playback interruption"
        )
        XCTAssertEqual(
            Set(reduction.nextState.queueState.queueOrder.map(\.id)),
            Set([song1.id, song2.id, "3", "4"])
        )
        XCTAssertTrue(
            reduction.transportCommands.isEmpty,
            "Active batch add should not emit transport commands to avoid playback pause"
        )
    }

    func testResyncActiveAddTransportRebuildsUpcomingAndBumpsRevision() throws {
        let song1 = Song(id: "1", title: "Song 1", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        let song2 = Song(id: "2", title: "Song 2", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        let song3 = Song(id: "3", title: "Song 3", artist: "Artist", albumTitle: "Album", artworkURL: nil)

        let queueState = QueueState(songPool: [song1, song2, song3], queueOrder: [song1, song2, song3], currentIndex: 1)
        let state = QueueEngineState(
            queueState: queueState,
            playbackState: .playing(song2),
            revision: 12,
            queueNeedsBuild: true
        )

        let reduction = try QueueEngineReducer.reduce(state: state, intent: .resyncActiveAddTransport)
        XCTAssertFalse(reduction.wasNoOp)
        XCTAssertEqual(reduction.nextState.revision, 13, "Retry resync should flow through normal revision bumping")
        XCTAssertFalse(reduction.nextState.queueNeedsBuild, "Successful retry resync should clear pending rebuild")
        XCTAssertEqual(reduction.nextState.queueState.currentSongId, song2.id)
        XCTAssertEqual(Set(reduction.nextState.queueState.queueOrder.map(\.id)), Set([song1.id, song2.id, song3.id]))

        guard case .replaceQueue(let queue, let startAtSongId, _, let revision) = reduction.transportCommands.first else {
            return XCTFail("Expected replaceQueue command for retry resync")
        }
        XCTAssertEqual(Set(queue.map(\.id)), Set([song1.id, song2.id, song3.id]))
        XCTAssertEqual(startAtSongId, song2.id)
        XCTAssertEqual(revision, 13)
    }

    func testSyncDeferredTransportMirrorsDomainOrderWithoutReshuffle() throws {
        let song1 = Song(id: "1", title: "Song 1", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        let song2 = Song(id: "2", title: "Song 2", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        let song3 = Song(id: "3", title: "Song 3", artist: "Artist", albumTitle: "Album", artworkURL: nil)

        // Domain queue order is [song2, song1, song3] — syncDeferredTransport should mirror this exactly.
        let queueState = QueueState(songPool: [song1, song2, song3], queueOrder: [song2, song1, song3], currentIndex: 0)
        let state = QueueEngineState(
            queueState: queueState,
            playbackState: .playing(song2),
            revision: 8,
            queueNeedsBuild: true
        )

        let reduction = try QueueEngineReducer.reduce(state: state, intent: .syncDeferredTransport)
        XCTAssertFalse(reduction.wasNoOp)
        XCTAssertEqual(reduction.nextState.revision, 9)
        XCTAssertFalse(reduction.nextState.queueNeedsBuild, "syncDeferredTransport should clear pending rebuild")

        // Queue order in domain should be unchanged (no reshuffle).
        XCTAssertEqual(
            reduction.nextState.queueState.queueOrder.map(\.id),
            [song2.id, song1.id, song3.id],
            "syncDeferredTransport must mirror existing domain order without reshuffling"
        )

        guard case .replaceQueue(let queue, let startAtSongId, _, let revision) = reduction.transportCommands.first else {
            return XCTFail("Expected replaceQueue command for syncDeferredTransport")
        }
        XCTAssertEqual(
            queue.map(\.id),
            [song2.id, song1.id, song3.id],
            "Transport command should mirror domain order exactly"
        )
        XCTAssertEqual(startAtSongId, song2.id)
        XCTAssertEqual(revision, 9)
    }

    func testSyncDeferredTransportNoOpsWhenInactiveOrMissingQueueOrNotNeeded() throws {
        let song = Song(id: "1", title: "Song 1", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        let inactiveState = QueueEngineState(
            queueState: QueueState(songPool: [song], queueOrder: [song], currentIndex: 0),
            playbackState: .stopped,
            revision: 3,
            queueNeedsBuild: true
        )
        let inactiveReduction = try QueueEngineReducer.reduce(state: inactiveState, intent: .syncDeferredTransport)
        XCTAssertTrue(inactiveReduction.wasNoOp)

        let noQueueState = QueueEngineState(
            queueState: QueueState(songPool: [song], queueOrder: [], currentIndex: 0),
            playbackState: .paused(song),
            revision: 3,
            queueNeedsBuild: true
        )
        let noQueueReduction = try QueueEngineReducer.reduce(state: noQueueState, intent: .syncDeferredTransport)
        XCTAssertTrue(noQueueReduction.wasNoOp)

        // No-ops when queueNeedsBuild is false (nothing to sync)
        let alreadySyncedState = QueueEngineState(
            queueState: QueueState(songPool: [song], queueOrder: [song], currentIndex: 0),
            playbackState: .playing(song),
            revision: 5,
            queueNeedsBuild: false
        )
        let alreadySyncedReduction = try QueueEngineReducer.reduce(state: alreadySyncedState, intent: .syncDeferredTransport)
        XCTAssertTrue(alreadySyncedReduction.wasNoOp, "syncDeferredTransport should no-op when queueNeedsBuild is false")
    }

    func testResyncActiveAddTransportNoOpsWhenInactiveOrMissingQueue() throws {
        let song = Song(id: "1", title: "Song 1", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        let inactiveState = QueueEngineState(
            queueState: QueueState(songPool: [song], queueOrder: [song], currentIndex: 0),
            playbackState: .stopped,
            revision: 3,
            queueNeedsBuild: true
        )
        let inactiveReduction = try QueueEngineReducer.reduce(state: inactiveState, intent: .resyncActiveAddTransport)
        XCTAssertTrue(inactiveReduction.wasNoOp)

        let noQueueState = QueueEngineState(
            queueState: QueueState(songPool: [song], queueOrder: [], currentIndex: 0),
            playbackState: .paused(song),
            revision: 3,
            queueNeedsBuild: true
        )
        let noQueueReduction = try QueueEngineReducer.reduce(state: noQueueState, intent: .resyncActiveAddTransport)
        XCTAssertTrue(noQueueReduction.wasNoOp)
    }
}
