import XCTest
@testable import Shfl

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
        let viewModel = composition.appViewModel
        let transport = try XCTUnwrap(
            viewModel.musicService as? DeterministicMusicService
        )

        XCTAssertFalse(composition.showsStartupSplash)

        await viewModel.onAppear()
        XCTAssertTrue(viewModel.isAuthorized)

        await viewModel.autofillLibrary()
        XCTAssertEqual(viewModel.player.songCount, 3)

        await viewModel.togglePlayback()
        XCTAssertEqual(viewModel.player.playbackState.currentSong?.title, "Low Tide")

        await viewModel.skipToNext()
        await waitUntil {
            viewModel.player.playbackState.currentSong?.title == "Second Wind"
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
