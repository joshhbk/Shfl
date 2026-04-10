import Foundation
import XCTest

/// Yields control several times so pending async tasks (like the MusicKit
/// playback state observer) can consume buffered stream values and update
/// observable state. Drop-in replacement for the old
/// `try await Task.sleep(nanoseconds: 100_000_000)` pattern — ~100x faster
/// because it exits as soon as the scheduler has drained pending tasks,
/// rather than waiting a fixed 100ms.
@MainActor
func waitForStateUpdate() async {
    // Multiple yields drain pending observer tasks across actor hops
    // (mock actor → AsyncStream → player MainActor observer → state update).
    // 30 yields handles the deepest chains we see in practice.
    for _ in 0..<30 {
        await Task.yield()
    }
}

/// Polls a condition until it's true or the timeout elapses. Use this when
/// you know the specific state you're waiting for — it exits as soon as the
/// condition is met.
@MainActor
func waitUntil(
    timeout: Duration = .seconds(1),
    _ condition: @MainActor () -> Bool,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    let deadline = ContinuousClock().now + timeout
    while !condition() {
        if ContinuousClock().now > deadline {
            XCTFail("waitUntil timed out after \(timeout)", file: file, line: line)
            return
        }
        await Task.yield()
    }
}
