import SwiftData
import UIKit
import XCTest
@testable import Shfl

@MainActor
final class AppModelLifecycleTests: XCTestCase {
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
        let model = AppModel(
            library: mockService,
            playbackTransport: mockService,
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

        try model.sessionDraft.add(song)
        await model.sessionHost.startFreshShuffle()
        await mockService.setPlaybackTime(42)

        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)

        let archive = SessionArchive(modelContext: modelContext)
        await waitUntil { (try? archive.load().session?.playbackPosition) == 42 }
        let saved = try await archive.loadAsync()

        XCTAssertEqual(saved.pool.map(\.id), ["1"])
        XCTAssertNotNil(saved.session)
        XCTAssertEqual(saved.session?.songOrder.map(\.id), ["1"])
        XCTAssertEqual(saved.session?.playbackPosition, 42)
    }

    func testDidEnterBackgroundNotificationTriggersSinglePersistenceCall() async throws {
        var persistCallCount = 0
        let model = AppModel(
            library: mockService,
            playbackTransport: mockService,
            modelContext: modelContext,
            appSettings: appSettings,
            lifecyclePersistenceHook: { persistCallCount += 1 }
        )
        _ = model

        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)

        for _ in 0..<10 {
            if persistCallCount == 1 { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        XCTAssertEqual(persistCallCount, 1, "A single background transition should trigger one persistence pass")
    }

    func testLaunchIsReadyWhenAppleMusicAccessWasAlreadyGranted() async {
        let model = makeModel(service: DeterministicMusicService())
        XCTAssertEqual(model.launchPhase, .loading)

        await model.onAppear()

        XCTAssertEqual(model.launchPhase, .ready)
    }

    func testLaunchWithoutAccessAsksAndReportsADenial() async {
        let model = makeModel(service: DeterministicMusicService(configuration: .init(isAuthorized: false)))

        await model.onAppear()
        XCTAssertEqual(model.launchPhase, .needsAuthorization)

        await model.requestAuthorization()
        XCTAssertEqual(model.launchPhase, .authorizationDenied)
    }

    private func makeModel(service: DeterministicMusicService) -> AppModel {
        AppModel(
            library: service,
            playbackTransport: service,
            modelContext: modelContext,
            appSettings: appSettings
        )
    }
}
