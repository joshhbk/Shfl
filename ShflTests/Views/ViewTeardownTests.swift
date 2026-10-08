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
        let draft = SessionDraftStore()
        try await showThenTearDown(
            SongPickerView(
                libraryCatalog: DeterministicMusicService(),
                initialSortOption: .mostPlayed,
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
                playbackTransport: service,
                onManageTapped: {}
            )
            .environment(\.sessionDraft, draft)
        )
    }

    func test_closingManageReleasesItsStateWithoutCrashing() async throws {
        let draft = SessionDraftStore()
        try draft.add(Song(id: "1", title: "One", artist: "Artist", albumTitle: "Album", artworkURL: nil))
        try await showThenTearDown(
            ManageView(
                player: ShufflePlayer(playbackTransport: DeterministicMusicService(), sessionDraft: draft),
                onAddTapped: {},
                onDismiss: {}
            )
            .environment(\.sessionDraft, draft)
        )
    }

    #if canImport(UIKit)
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
    #else
    private func showThenTearDown(_ view: some View) async throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 800),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        weak var weakHost: NSHostingController<AnyView>?
        do {
            let host = NSHostingController(rootView: AnyView(view))
            weakHost = host
            window.contentViewController = host
            window.orderFront(nil)
            try await Task.sleep(for: .milliseconds(300))
            window.contentViewController = NSViewController()
        }
        // SwiftUI releases view state on a later run-loop pass, outside any task.
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertNil(weakHost)
        window.close()
    }
    #endif
}
