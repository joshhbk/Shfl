import XCTest
@testable import Shfl
@testable import ShflCore

@MainActor
final class AppCompositionTests: XCTestCase {
    func testLaunchSelectionUsesDeterministicCompositionForScenariosAndTests() {
        XCTAssertEqual(
            AppComposition.selectedMode(arguments: ["Shfl", "--deterministic"], environment: [:]),
            .deterministic
        )
        XCTAssertEqual(
            AppComposition.selectedMode(
                arguments: ["Shfl"],
                environment: ["XCTestConfigurationFilePath": "/tmp/tests.xctestconfiguration"]
            ),
            .deterministic
        )
        XCTAssertEqual(
            AppComposition.selectedMode(arguments: ["Shfl"], environment: [:]),
            .live
        )
    }

    func testDeterministicCompositionRunsKnownPlaybackScenario() async throws {
        let composition = try AppComposition.make(mode: .deterministic)
        let model = composition.appModel
        let transport = try XCTUnwrap(
            model.playbackTransport as? DeterministicMusicService
        )

        XCTAssertFalse(composition.showsStartupSplash)

        await model.onAppear()
        XCTAssertEqual(model.launchPhase, .ready)

        // Play on an empty draft autofills it from the library first.
        await model.sessionHost.togglePlayback()
        XCTAssertEqual(model.sessionDraft.songCount, 3)
        XCTAssertEqual(model.player.playbackState.currentSong?.title, "Low Tide")

        try await model.player.skipToNext()
        await waitUntil {
            model.player.playbackState.currentSong?.title == "Second Wind"
        }

        let request = await transport.lastLoadRequest
        let loadCount = await transport.loadCallCount
        XCTAssertEqual(
            request?.queue.map(\.title),
            ["Low Tide", "Second Wind", "Afterglow"]
        )
        XCTAssertEqual(request?.playbackPosition, 0)
        XCTAssertEqual(loadCount, 1)
    }

    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async {
        for _ in 0..<1_000 {
            if condition() { return }
            await Task.yield()
        }
        XCTFail("Timed out waiting for deterministic playback event")
    }
}
