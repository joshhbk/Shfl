import SwiftData
import UIKit
import XCTest
@testable import Shfl

@MainActor
final class AppViewModelLifecycleTests: XCTestCase {
    private var container: ModelContainer!
    private var modelContext: ModelContext!
    private var mockService: DeterministicMusicService!
    private var appSettings: AppSettings!

    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: PersistedSession.self,
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
        let viewModel = AppViewModel(
            musicService: mockService,
            modelContext: modelContext,
            appSettings: appSettings
        )

        let song = Song(
            id: "1",
            title: "Song 1",
            artist: "Artist 1",
            albumTitle: "Album 1",
            artworkURL: nil
        )

        try await viewModel.addSong(song)
        try await viewModel.player.prepareQueue(algorithm: appSettings.shuffleAlgorithm)
        await mockService.setPlaybackTime(42)

        viewModel.handleDidEnterBackground()

        let archive = SessionArchive(modelContext: modelContext)
        let saved = try await archive.loadAsync()

        XCTAssertEqual(saved.pool.map(\.id), ["1"])
        XCTAssertNotNil(saved.session)
        XCTAssertEqual(saved.session?.songOrder.map(\.id), ["1"])
        XCTAssertEqual(saved.session?.playbackPosition, 42)
    }

    func testDidEnterBackgroundNotificationTriggersSinglePersistenceCall() async throws {
        var persistCallCount = 0
        let viewModel = AppViewModel(
            musicService: mockService,
            modelContext: modelContext,
            appSettings: appSettings,
            lifecyclePersistenceHook: { persistCallCount += 1 }
        )
        _ = viewModel

        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)

        for _ in 0..<10 {
            if persistCallCount == 1 { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        XCTAssertEqual(persistCallCount, 1, "A single background transition should trigger one persistence pass")
    }
}
