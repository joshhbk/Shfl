import AppKit
import SwiftUI
import XCTest
@testable import ShflMac
import ShflComposition
import ShflCore

// Under Xcode 27 these crash if a main-actor class loses its explicit `deinit {}`.
@MainActor
final class ViewTeardownTests: XCTestCase {
    func test_closingTheMainWindowReleasesItsStateWithoutCrashing() async throws {
        let model = AppModel.preview(draft: DeterministicSongs.make(3))
        await model.launch()
        try await showThenTearDown(model) { LaunchRootView(model: model) }
    }

    func test_leavingEachPlaceReleasesItsStateWithoutCrashing() async throws {
        let model = AppModel.preview()
        for place in SidebarItem.allCases {
            try await showThenTearDown(model) { PlaceHost(place: place) }
        }
    }

    func test_closingTheNowPlayingBarReleasesItsClockWithoutCrashing() async throws {
        let model = AppModel.preview()
        try await showThenTearDown(model) {
            NowPlayingBar()
        }
    }

    func test_closingSettingsReleasesItsStateWithoutCrashing() async throws {
        try await showThenTearDown(.preview()) { ShflSettingsView() }
    }

    private func showThenTearDown(
        _ model: AppModel,
        @ViewBuilder _ makeView: () -> some View
    ) async throws {
        weak var weakHost: NSHostingController<AnyView>?
        do {
            let shell = Shell(model: model, beep: {})
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1000, height: 640),
                styleMask: [.titled],
                backing: .buffered,
                defer: false
            )
            window.isReleasedWhenClosed = false
            let host = NSHostingController(rootView: AnyView(makeView().shellEnvironment(shell)))
            weakHost = host
            window.contentViewController = host
            window.orderBack(nil)
            try await Task.sleep(for: .milliseconds(300))
            window.contentViewController = nil
            window.close()
        }
        // SwiftUI releases view state on a later run-loop pass, outside any task.
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertNil(weakHost)
    }
}

struct PlaceHost: View {
    let place: SidebarItem
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        DetailColumn(place: place, isSearchFocused: $isSearchFocused)
    }
}
