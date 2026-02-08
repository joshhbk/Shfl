import SwiftData
import UIKit
import XCTest
@testable import Shfl

@MainActor
final class AppPlaybackSessionCoordinatorTests: XCTestCase {
    private var container: ModelContainer!
    private var modelContext: ModelContext!
    private var mockService: MockMusicService!
    private var appSettings: AppSettings!

    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: PersistedSong.self,
            PersistedPlaybackState.self,
            configurations: config
        )
        modelContext = container.mainContext
        mockService = MockMusicService()
        appSettings = AppSettings()
    }

    override func tearDown() {
        container = nil
        modelContext = nil
        mockService = nil
        appSettings = nil
    }

    func testHandleDidEnterBackgroundPersistsSongsAndPlaybackState() async throws {
        let player = ShufflePlayer(musicService: mockService)
        let playbackCoordinator = PlaybackCoordinator(player: player, appSettings: appSettings)
        let coordinator = makeCoordinator(player: player, playbackCoordinator: playbackCoordinator)

        let song = Song(
            id: "1",
            title: "Song 1",
            artist: "Artist 1",
            albumTitle: "Album 1",
            artworkURL: nil
        )

        try await playbackCoordinator.addSong(song)
        try await playbackCoordinator.prepareQueue()
        await mockService.setMockPlaybackTime(42)

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
        let player = ShufflePlayer(musicService: mockService)
        let playbackCoordinator = PlaybackCoordinator(player: player, appSettings: appSettings)

        var persistCallCount = 0
        let coordinator = makeCoordinator(
            player: player,
            playbackCoordinator: playbackCoordinator,
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

    private func makeCoordinator(
        player: ShufflePlayer,
        playbackCoordinator: PlaybackCoordinator,
        lifecyclePersistenceHook: (() -> Void)? = nil
    ) -> AppPlaybackSessionCoordinator {
        let repository = SongRepository(modelContext: modelContext)
        let playbackStateRepository = PlaybackStateRepository(modelContext: modelContext)
        let scrobbleTracker = ScrobbleTracker(
            scrobbleManager: ScrobbleManager(transports: []),
            musicService: mockService
        )

        return AppPlaybackSessionCoordinator(
            player: player,
            playbackCoordinator: playbackCoordinator,
            musicService: mockService,
            repository: repository,
            playbackStateRepository: playbackStateRepository,
            scrobbleTracker: scrobbleTracker,
            lifecyclePersistenceHook: lifecyclePersistenceHook
        )
    }
}
