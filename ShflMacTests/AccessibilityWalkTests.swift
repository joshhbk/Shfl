import AppKit
import ApplicationServices
import SwiftUI
import XCTest
@testable import ShflMac
import ShflComposition
import ShflCore
import ShflDeterministic

// SwiftUI builds its accessibility tree only for an AX client, so walk through the AX API like VoiceOver does.
@MainActor
final class AccessibilityWalkTests: XCTestCase {
    private let songs = DeterministicSongs.make(300)

    func test_walkingEveryPlaceDoesNotCrash() async throws {
        let model = AppModel.preview(library: DeterministicLibrary(songs: songs), draft: Array(songs.prefix(110)))
        await model.sessionHost.startFreshShuffle()
        for place in SidebarItem.allCases {
            let nodes = try await walk(PlaceHost(place: place), model: model)
            XCTAssertGreaterThan(nodes, 20, "\(place)")
        }
    }

    func test_walkingTheWholeWindowDoesNotCrash() async throws {
        let model = AppModel.preview(library: DeterministicLibrary(songs: songs), draft: Array(songs.prefix(110)))
        await model.launch()
        let nodes = try await walk(LaunchRootView(model: model), model: model)
        XCTAssertGreaterThan(nodes, 100)
    }

    func test_walkingSettingsDoesNotCrash() async throws {
        let model = AppModel.preview()
        _ = try await walk(ShflSettingsView(), model: model)
        _ = try await walk(PlaybackSettingsTab(), model: model)
        _ = try await walk(LibrarySettingsTab(), model: model)
        _ = try await walk(LastFMSettingsTab(), model: model)
    }

    func test_walkingTheDesignCatalogDoesNotCrash() async throws {
        let nodes = try await walk(DesignCatalogView(), model: .preview())
        XCTAssertGreaterThan(nodes, 50)
    }

    /// Shows `view` in a window shorter than its content, so lists and tables have rows out of sight.
    private func walk(_ view: some View, model: AppModel) async throws -> Int {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 400),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(
            rootView: view.shellEnvironment(Shell(model: model, beep: {}))
        )
        window.orderBack(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(400))

        // In-process AX calls run on the calling thread, which must be the main one.
        var visited = 0
        var pending = [AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)]
        while let element = pending.popLast() {
            visited += 1
            var children: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success {
                pending.append(contentsOf: (children as? [AXUIElement]) ?? [])
            }
        }
        // SwiftUI renders the rows the walk asked for on the next pass.
        try await Task.sleep(for: .milliseconds(300))
        return visited
    }
}
