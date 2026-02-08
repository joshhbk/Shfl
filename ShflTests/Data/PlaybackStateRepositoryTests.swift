import SwiftData
import XCTest
@testable import Shfl

final class PlaybackStateRepositoryTests: XCTestCase {
    private var container: ModelContainer!
    private var repository: PlaybackStateRepository!

    private enum InjectedFailure: Error { case save }

    @MainActor
    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: PersistedPlaybackState.self, configurations: config)
        repository = PlaybackStateRepository(modelContext: container.mainContext)
    }

    override func tearDown() {
        container = nil
        repository = nil
    }

    @MainActor
    func testSaveAndLoadPlaybackState() async throws {
        let state = PersistedPlaybackState(
            currentSongId: "song-1",
            playbackPosition: 42,
            wasPlaying: false,
            queueOrder: ["song-1", "song-2"],
            playedSongIds: ["song-9"]
        )

        try repository.savePlaybackState(state)

        let loaded = try await repository.loadPlaybackStateAsync()
        XCTAssertEqual(loaded?.currentSongId, "song-1")
        XCTAssertEqual(loaded?.playbackPosition, 42)
        XCTAssertEqual(loaded?.queueOrder, ["song-1", "song-2"])
        XCTAssertEqual(loaded?.playedSongIds, ["song-9"])
    }

    @MainActor
    func testSavePlaybackFailureKeepsPreviousSnapshotRecoverable() async throws {
        let original = PersistedPlaybackState(
            currentSongId: "original",
            playbackPosition: 10,
            wasPlaying: false,
            queueOrder: ["original"],
            playedSongIds: []
        )
        try repository.savePlaybackState(original)

        let failingRepository = PlaybackStateRepository(
            modelContext: container.mainContext,
            saveHandler: { throw InjectedFailure.save }
        )
        let replacement = PersistedPlaybackState(
            currentSongId: "replacement",
            playbackPosition: 99,
            wasPlaying: false,
            queueOrder: ["replacement"],
            playedSongIds: ["replacement"]
        )

        XCTAssertThrowsError(try failingRepository.savePlaybackState(replacement))

        let recoveredRepository = PlaybackStateRepository(modelContext: ModelContext(container))
        let loaded = try await recoveredRepository.loadPlaybackStateAsync()
        XCTAssertEqual(loaded?.currentSongId, "original")
        XCTAssertEqual(loaded?.queueOrder, ["original"])
        XCTAssertEqual(loaded?.playedSongIds, [])
    }
}
