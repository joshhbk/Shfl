import Foundation
import XCTest

@MainActor
public func waitForStateUpdate() async {
    // Multiple yields drain pending observer tasks across actor hops
    // (mock actor → AsyncStream → player MainActor observer → state update).
    // 30 yields handles the deepest chains we see in practice.
    for _ in 0..<30 {
        await Task.yield()
    }
}

@MainActor
public func waitUntil(
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
