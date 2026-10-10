import SwiftUI
import XCTest
@testable import Shfl

/// Builds real screens in a window and lets SwiftUI tear them down, the way
/// closing a sheet or popping a screen does. Under Xcode 27, a main-actor class
/// released inside another object's deinit aborts in the Swift runtime unless
/// its deinit is nonisolated, so these guard the explicit `deinit {}`s.
@MainActor
final class ViewTeardownTests: XCTestCase {
    func test_closingTheSongPickerReleasesItsStateWithoutCrashing() async throws {
        let suiteName = "ViewTeardownTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let draft = SessionDraftStore()
        try await showThenTearDown(
            SongPickerView(
                libraryCatalog: DeterministicMusicService(),
                libraryPreferences: LibraryPreferences(defaults: defaults),
                onDismiss: {}
            )
            .environment(\.sessionDraft, draft)
        )
    }

    func test_leavingThePlayerReleasesItsStateWithoutCrashing() async throws {
        let service = DeterministicMusicService()
        let draft = SessionDraftStore()
        try await showThenTearDown(
            PlayerView(
                player: ShufflePlayer(playbackTransport: service, sessionDraft: draft),
                playbackTransport: service
            )
            .environment(\.sessionDraft, draft)
        )
    }

    func test_leavingLastFMSettingsReleasesItsStateWithoutCrashing() async throws {
        try await showThenTearDown(
            NavigationStack {
                LastFMSettingsView()
            }
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
