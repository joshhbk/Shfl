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
            playedSongIds: []
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
}
