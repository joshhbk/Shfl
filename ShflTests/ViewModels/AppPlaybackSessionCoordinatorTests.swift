import SwiftData
import UIKit
import XCTest
@testable import Shfl

@MainActor
final class AppPlaybackSessionCoordinatorTests: XCTestCase {
    private var container: ModelContainer!
    private var modelContext: ModelContext!
    private var mockService: DeterministicMusicService!
    private var appSettings: AppSettings!

    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: PersistedSong.self,
            PersistedPlaybackState.self,
            configurations: config
        )
        modelContext = container.mainContext
        mockService = DeterministicMusicService()
        appSettings = AppSettings()
    }

    override func tearDown() {
        container = nil
        modelContext = nil
        mockService = nil
        appSettings = nil
    }

    func testHandleDidEnterBackgroundPersistsSongsAndPlaybackState() async throws {
        let player = ShufflePlayer(playbackTransport: mockService)
        let coordinator = makeCoordinator(player: player)

        let song = Song(
            id: "1",
            title: "Song 1",
            artist: "Artist 1",
            albumTitle: "Album 1",
            artworkURL: nil
        )

        try await player.addSong(song)
        try await player.prepareQueue(algorithm: appSettings.shuffleAlgorithm)
        await mockService.setPlaybackTime(42)

        coordinator.handleDidEnterBackground()

        let songRepository = SongRepository(modelContext: modelContext)
        let playbackStateRepository = PlaybackStateRepository(modelContext: modelContext)
        let persistedSongs = try songRepository.loadSongs()
        let persistedPlaybackState = try await playbackStateRepository.loadPlaybackStateAsync()

        XCTAssertEqual(persistedSongs.map(\.id), ["1"])
        XCTAssertNotNil(persistedPlaybackState)
        XCTAssertEqual(persistedPlaybackState?.queueOrder, ["1"])
        XCTAssertEqual(persistedPlaybackState?.playbackPosition, 42)
    }

    func testDidEnterBackgroundNotificationTriggersSinglePersistenceCall() async throws {
        let player = ShufflePlayer(playbackTransport: mockService)

        var persistCallCount = 0
        let coordinator = makeCoordinator(
            player: player,
            lifecyclePersistenceHook: { persistCallCount += 1 }
        )
        _ = coordinator

        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)

        for _ in 0..<10 {
            if persistCallCount == 1 { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        XCTAssertEqual(persistCallCount, 1)
    }

    func testTransitionsDriveScrobblingAndPersistenceAcrossRestoreResumeAndFreshShuffle() async throws {
        let player = ShufflePlayer(playbackTransport: mockService)
        let nowPlaying = expectation(description: "Now playing for each listening session")
        nowPlaying.expectedFulfillmentCount = 2
        let scrobbleTransport = RecordingScrobbleTransport(nowPlaying: nowPlaying)
        let tracker = ScrobbleTracker(
            scrobbleManager: ScrobbleManager(transports: [scrobbleTransport]),
            playbackTransport: mockService
        )
        let coordinator = makeCoordinator(player: player, scrobbleTracker: tracker)
        let song = Song(id: "one", title: "One", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        try player.seedSongs([song])
        let restored = await player.restoreSession(
            queueOrder: [song.id], currentSongId: song.id,
            playedIds: [], playbackPosition: 42, seed: 1
        )
        XCTAssertTrue(restored)
        try await player.play()
        await player.pause()
        try await player.play()
        try await player.startFreshShuffle(seed: 2)
        await fulfillment(of: [nowPlaying], timeout: 2)

        let saved = try PlaybackStateRepository(modelContext: modelContext).loadPlaybackState()
        XCTAssertEqual(saved?.currentSongId, song.id)
        XCTAssertEqual(saved?.seed, 2)
        XCTAssertEqual(saved?.playbackPosition, 0)
        withExtendedLifetime(coordinator) {}
    }

    func testCoordinatorCanBeReleasedWhileWaitingForTransitions() async {
        let player = ShufflePlayer(playbackTransport: mockService)
        var coordinator: AppPlaybackSessionCoordinator? = makeCoordinator(player: player)
        weak var releasedCoordinator = coordinator
        await Task.yield()
        coordinator = nil
        XCTAssertNil(releasedCoordinator)
    }

    private func makeCoordinator(
        player: ShufflePlayer,
        scrobbleTracker: ScrobbleTracker? = nil,
        lifecyclePersistenceHook: (() -> Void)? = nil
    ) -> AppPlaybackSessionCoordinator {
        let songRepository = SongRepository(modelContext: modelContext)
        let playbackStateRepository = PlaybackStateRepository(modelContext: modelContext)
        let sessionSnapshotService = SessionSnapshotService(
            songRepository: songRepository,
            playbackStateRepository: playbackStateRepository
        )
        let scrobbleTracker = scrobbleTracker ?? ScrobbleTracker(
            scrobbleManager: ScrobbleManager(transports: []),
            playbackTransport: mockService
        )

        return AppPlaybackSessionCoordinator(
            player: player,
            authorizer: mockService,
            playbackTransport: mockService,
            sessionSnapshotService: sessionSnapshotService,
            scrobbleTracker: scrobbleTracker,
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
