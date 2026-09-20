import SwiftData
import XCTest
@testable import Shfl

@MainActor
final class SessionSnapshotServiceTests: XCTestCase {
    private var container: ModelContainer!
    private var modelContext: ModelContext!
    private var songRepository: SongRepository!
    private var playbackStateRepository: PlaybackStateRepository!
    private var service: SessionSnapshotService!

    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: PersistedSong.self,
            PersistedPlaybackState.self,
            configurations: config
        )
        modelContext = container.mainContext
        songRepository = SongRepository(modelContext: modelContext)
        playbackStateRepository = PlaybackStateRepository(modelContext: modelContext)
        service = SessionSnapshotService(
            songRepository: songRepository,
            playbackStateRepository: playbackStateRepository
        )
    }

    override func tearDown() {
        container = nil
        modelContext = nil
        songRepository = nil
        playbackStateRepository = nil
        service = nil
    }

    func testTransitionPersistsCapturedSessionAfterPlayerHasMovedOn() async throws {
        let transport = DeterministicMusicService()
        let player = ShufflePlayer(playbackTransport: transport)
        let song = Song(id: "one", title: "One", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        try player.seedSongs([song])
        try await player.startFreshShuffle(seed: 42)
        var iterator = player.playbackTransitions.makeAsyncIterator()
        let next = await iterator.next()
        let captured = try XCTUnwrap(next)
        try await player.startFreshShuffle(seed: 99)

        try service.savePlaybackTransition(captured, songs: player.allSongs)
        let saved = try service.loadCurrent()
        XCTAssertEqual(saved.playback?.seed, 42)
        XCTAssertEqual(saved.playback?.currentSongId, song.id)
        XCTAssertEqual(saved.playback?.playbackPosition, captured.playbackTime)
    }

    func testDelayedTransitionCannotOverwriteNewerLifecycleSave() async throws {
        let transport = DeterministicMusicService()
        let player = ShufflePlayer(playbackTransport: transport)
        let song = Song(id: "one", title: "One", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        try player.seedSongs([song])
        try await player.startFreshShuffle(seed: 42)
        var iterator = player.playbackTransitions.makeAsyncIterator()
        let next = await iterator.next()
        let delayed = try XCTUnwrap(next)

        await transport.setPlaybackTime(42)
        try service.saveCurrentSession(from: player, playbackTime: transport.currentPlaybackTime)
        try service.savePlaybackTransition(delayed, songs: player.allSongs)
        XCTAssertEqual(try service.loadCurrent().playback?.playbackPosition, 42)
    }

    func testPauseAndResumeTransitionsDoNotOverwriteSavedPosition() async throws {
        let song = Song(id: "one", title: "One", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        let session = ListeningSession(songOrder: [song], algorithm: .noRepeat, seed: 42)
        try service.savePlaybackTransition(PlaybackTransition(
            state: .playing(song), session: session, playbackTime: 12,
            songChanged: true, startsSong: true
        ), songs: [song])
        for state in [PlaybackState.paused(song), .playing(song)] {
            try service.savePlaybackTransition(PlaybackTransition(
                state: state, session: session, playbackTime: 50,
                songChanged: false, startsSong: false
            ), songs: [song])
        }
        XCTAssertEqual(try service.loadCurrent().playback?.playbackPosition, 12)
    }

    func testLoadReturnsEmptySnapshotWhenNothingPersisted() async throws {
        let snapshot = try await service.load()

        XCTAssertEqual(snapshot, .empty)
    }

    func testSaveAndLoadSessionSnapshot() async throws {
        let song = Song(
            id: "1",
            title: "Song 1",
            artist: "Artist 1",
            albumTitle: "Album 1",
            artworkURL: nil
        )
        let playback = PlaybackSessionSnapshot(
            currentSongId: "1",
            playbackPosition: 42,
            savedAt: Date(timeIntervalSince1970: 1_700_000_000),
            queueOrder: ["1"],
            playedSongIds: [],
            algorithm: .artistSpacing,
            seed: 9_876
        )

        try service.save(
            AppSessionSnapshot(
                songs: [song],
                playback: playback
            )
        )

        let loaded = try await service.load()
        XCTAssertEqual(loaded.songs, [song])
        XCTAssertEqual(loaded.playback, playback)
    }

    func testSaveWithoutPlaybackClearsPersistedPlaybackState() async throws {
        let existingPlayback = PlaybackSessionSnapshot(
            currentSongId: "1",
            playbackPosition: 42,
            savedAt: Date(timeIntervalSince1970: 1_700_000_000),
            queueOrder: ["1"],
            playedSongIds: []
        )
        try playbackStateRepository.savePlaybackState(existingPlayback)

        let song = Song(
            id: "2",
            title: "Song 2",
            artist: "Artist 2",
            albumTitle: "Album 2",
            artworkURL: nil
        )
        try service.save(
            AppSessionSnapshot(
                songs: [song],
                playback: nil
            )
        )

        let loaded = try await service.load()
        XCTAssertEqual(loaded.songs, [song])
        XCTAssertNil(loaded.playback)
    }

    func testClearPlaybackLeavesSongsUntouched() async throws {
        let song = Song(
            id: "1",
            title: "Song 1",
            artist: "Artist 1",
            albumTitle: "Album 1",
            artworkURL: nil
        )
        try songRepository.saveSongs([song])
        try playbackStateRepository.savePlaybackState(
            PlaybackSessionSnapshot(
                currentSongId: "1",
                playbackPosition: 42,
                savedAt: Date(timeIntervalSince1970: 1_700_000_000),
                queueOrder: ["1"],
                playedSongIds: []
            )
        )

        try service.clearPlayback()

        let loaded = try await service.load()
        XCTAssertEqual(loaded.songs, [song])
        XCTAssertNil(loaded.playback)
    }

    // MARK: - Stale detection (policy deepened into service)

    func testIsPlaybackStateStaleReturnsFalseForRecentState() {
        let recent = PlaybackSessionSnapshot(
            currentSongId: "1",
            playbackPosition: 30,
            savedAt: Date().addingTimeInterval(-3600), // 1 hour ago
            queueOrder: ["1"],
            playedSongIds: []
        )

        XCTAssertFalse(service.isPlaybackStateStale(recent))
    }

    func testIsPlaybackStateStaleReturnsTrueForOldState() {
        let old = PlaybackSessionSnapshot(
            currentSongId: "1",
            playbackPosition: 30,
            savedAt: Date().addingTimeInterval(-(8 * 24 * 3600)), // 8 days ago
            queueOrder: ["1"],
            playedSongIds: []
        )

        XCTAssertTrue(service.isPlaybackStateStale(old))
    }

    func testIsPlaybackStateStaleReturnsTrueWhenDateCalculationFails() {
        let distantPast = PlaybackSessionSnapshot(
            currentSongId: "1",
            playbackPosition: 0,
            savedAt: Date.distantPast,
            queueOrder: [],
            playedSongIds: []
        )

        XCTAssertTrue(service.isPlaybackStateStale(distantPast))
    }
}
