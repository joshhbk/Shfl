import AppKit
import SwiftUI
import XCTest
@testable import ShflMac
import ShflComposition
import ShflCore

// Sends real AppKit events to a hosted tray, so clicks, arrows and ⌫ go through SwiftUI's focus system.
@MainActor
final class PicksTrayKeyboardTests: XCTestCase {
    func test_clickingTheTrayThenArrowAndDeleteRemovesThePickBeforeTheNewest() async throws {
        let songs = DeterministicSongs.make(3)
        let shell = Shell(model: .preview(draft: songs), beep: {})
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 400),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(
            rootView: PicksTray().frame(width: 260).padding(20).frame(maxHeight: .infinity, alignment: .top)
                .shellEnvironment(shell)
        )
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(300))

        let contentHeight = try XCTUnwrap(window.contentView).bounds.height
        click(window, at: NSPoint(x: 30, y: contentHeight - 30))
        try await Task.sleep(for: .milliseconds(200))
        press(window, keyCode: 123, characters: String(UnicodeScalar(NSLeftArrowFunctionKey)!))
        try await Task.sleep(for: .milliseconds(200))
        press(window, keyCode: 51, characters: "\u{7F}")
        try await Task.sleep(for: .milliseconds(200))

        XCTAssertEqual(shell.drafting.draft.songs.map(\.id), [songs[0].id, songs[2].id])
    }

    private func click(_ window: NSWindow, at point: NSPoint) {
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
            )
            window.sendEvent(event!)
        }
    }

    private func press(_ window: NSWindow, keyCode: UInt16, characters: String) {
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            let event = NSEvent.keyEvent(
                with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, characters: characters,
                charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode
            )
            window.sendEvent(event!)
        }
    }
}
