import SwiftUI
import XCTest
@testable import Shfl
import ShflComposition
import ShflCore
import ShflDeterministic

/// Builds real screens in a window and lets SwiftUI tear them down, the way
/// closing a sheet or popping a screen does. Under Xcode 27, a main-actor class
/// released inside another object's deinit aborts in the Swift runtime unless
/// its deinit is nonisolated, so these guard the explicit `deinit {}`s.
@MainActor
final class ViewTeardownTests: XCTestCase {
    func test_closingTheSongPickerReleasesItsStateWithoutCrashing() async throws {
        let model = AppModel.preview(library: .empty)
        try await showThenTearDown(
            SongPickerView(
                browser: model.makeLibraryBrowser(),
                editor: model.makeDraftEditor(),
                onDismiss: {}
            )
            .environment(\.sessionDraft, model.sessionDraft)
            .environment(model)
        )
    }

    func test_leavingThePlayerReleasesItsStateWithoutCrashing() async throws {
        let model = AppModel.preview(library: .empty)
        try await showThenTearDown(
            PlayerView(
                player: model.player,
                playbackClock: model.makePlaybackClock()
            )
            .environment(\.sessionDraft, model.sessionDraft)
        )
    }

    func test_leavingLastFMSettingsReleasesItsStateWithoutCrashing() async throws {
        try await showThenTearDown(
            NavigationStack {
                LastFMSettingsView()
            }
            .environment(AppModel.preview(library: .empty))
        )
    }

    private func showThenTearDown(_ view: some View) async throws {
        let window = UIWindow(frame: UIScreen.main.bounds)
        weak var weakHost: UIHostingController<AnyView>?
        do {
            let host = UIHostingController(rootView: AnyView(view))
            weakHost = host
            window.rootViewController = host
            window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(300))
            window.rootViewController = UIViewController()
        }
        // SwiftUI releases view state on a later run-loop pass, outside any task.
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertNil(weakHost)
    }
}
