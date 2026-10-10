import Foundation
import XCTest

@MainActor
public func waitForStateUpdate() async {
    // 30 yields drains the deepest hop chain in the tests (mock actor → stream → main-actor observer).
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
