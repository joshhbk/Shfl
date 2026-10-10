import SwiftData
import XCTest
@testable import ShflComposition
@testable import ShflCore
@testable import ShflDeterministic
import ShflTestSupport

@MainActor
final class AppModelLifecycleTests: XCTestCase {
    private var container: ModelContainer!
    private var modelContext: ModelContext!
    private var mockService: DeterministicMusicService!
    private var libraryPreferences: LibraryPreferences!
    private var defaults: UserDefaults!
    private var defaultsSuiteName: String!

    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: PersistedSession.self,
            configurations: config
        )
        modelContext = container.mainContext
        mockService = DeterministicMusicService()
        defaultsSuiteName = "AppModelLifecycleTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)
        libraryPreferences = LibraryPreferences(defaults: defaults)
    }

    override func tearDown() {
        container = nil
        modelContext = nil
        mockService = nil
        libraryPreferences = nil
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        defaults = nil
    }

    func testSceneDidLeaveForegroundPersistsSongsAndPlaybackState() async throws {
        let model = AppModel(
            library: mockService,
            playbackTransport: mockService,
            modelContainer: container,
            libraryPreferences: libraryPreferences,
            savedAlgorithm: SavedShuffleAlgorithm(defaults: defaults),
            lastFMTransport: nil,
            artworkStore: nil
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

        model.sessionHost.sceneDidLeaveForeground()

        let saved = try await SessionArchive(modelContext: modelContext).loadAsync()

        XCTAssertEqual(saved.pool.map(\.id), ["1"])
        XCTAssertNotNil(saved.session)
        XCTAssertEqual(saved.session?.songOrder.map(\.id), ["1"])
        XCTAssertEqual(saved.session?.playbackPosition, 42)
    }

    func testSceneDidLeaveForegroundRunsOnePersistencePass() async throws {
        var persistCallCount = 0
        let model = AppModel(
            library: mockService,
            playbackTransport: mockService,
            modelContainer: container,
            libraryPreferences: libraryPreferences,
            savedAlgorithm: SavedShuffleAlgorithm(defaults: defaults),
            lastFMTransport: nil,
            artworkStore: nil,
            lifecyclePersistenceHook: { persistCallCount += 1 }
        )

        model.sessionHost.sceneDidLeaveForeground()

        XCTAssertEqual(persistCallCount, 1, "A single background transition should trigger one persistence pass")
    }

    func testLaunchIsReadyWhenAppleMusicAccessWasAlreadyGranted() async {
        let model = makeModel(service: DeterministicMusicService())
        XCTAssertEqual(model.launchPhase, .loading)

        await model.launch()

        XCTAssertEqual(model.launchPhase, .ready)
    }

    func testLaunchWithoutAccessAsksAndReportsADenial() async {
        let model = makeModel(service: DeterministicMusicService(configuration: .init(isAuthorized: false)))

        await model.launch()
        XCTAssertEqual(model.launchPhase, .needsAuthorization)

        await model.requestAuthorization()
        XCTAssertEqual(model.launchPhase, .authorizationDenied)
    }

    func testDraftStartsWithTheSavedAlgorithmAndSavesEachNewOne() async {
        SavedShuffleAlgorithm(defaults: defaults).save(.artistSpacing)
        let model = makeModel(service: mockService)
        XCTAssertEqual(model.sessionDraft.algorithm, .artistSpacing)

        model.sessionDraft.stage(.weightedByRecency)

        await waitUntil { self.defaults.string(forKey: "shuffleAlgorithm") == "weightedByRecency" }
        XCTAssertEqual(SavedShuffleAlgorithm(defaults: defaults).load(), .weightedByRecency)
    }

    func testConcurrentLaunchesRestoreOnce() async throws {
        let first = makeModel(service: mockService)
        try first.sessionDraft.add(Song(id: "1", title: "One", artist: "Artist", albumTitle: "Album", artworkURL: nil))
        await first.sessionHost.startFreshShuffle()
        first.sceneDidLeaveForeground()

        let service = DeterministicMusicService()
        let model = makeModel(service: service)
        async let launchA: Void = model.launch()
        async let launchB: Void = model.launch()
        _ = await (launchA, launchB)
        await model.launch()

        let restoreLoads = await service.loadCallCount
        XCTAssertEqual(restoreLoads, 1)
        XCTAssertEqual(model.launchPhase, .ready)
    }

    private func makeModel(service: DeterministicMusicService) -> AppModel {
        AppModel(
            library: service,
            playbackTransport: service,
            modelContainer: container,
            libraryPreferences: libraryPreferences,
            savedAlgorithm: SavedShuffleAlgorithm(defaults: defaults),
            lastFMTransport: nil,
            artworkStore: nil
        )
    }
}
