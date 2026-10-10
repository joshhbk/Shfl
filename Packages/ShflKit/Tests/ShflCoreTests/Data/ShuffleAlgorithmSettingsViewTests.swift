import XCTest
import SwiftUI
@testable import ShflCore

final class ShuffleAlgorithmSettingsViewTests: XCTestCase {

    private let suiteName = "ShuffleAlgorithmSettingsViewTests"

    override func tearDown() {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    @MainActor
    func testDefaultAlgorithmIsNoRepeat() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        XCTAssertEqual(SavedShuffleAlgorithm(defaults: defaults).load(), .noRepeat)
    }

    @MainActor
    func testAlgorithmPersistsToTheShuffleAlgorithmKey() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        SavedShuffleAlgorithm(defaults: defaults).save(.artistSpacing)

        XCTAssertEqual(defaults.string(forKey: "shuffleAlgorithm"), "artistSpacing")
        XCTAssertEqual(SavedShuffleAlgorithm(defaults: defaults).load(), .artistSpacing)
    }

    func testAllAlgorithmsHaveDescriptions() {
        for algorithm in ShuffleAlgorithm.allCases {
            XCTAssertFalse(algorithm.description.isEmpty, "\(algorithm) should have description")
        }
    }

    func testAllAlgorithmsHaveDisplayNames() {
        for algorithm in ShuffleAlgorithm.allCases {
            XCTAssertFalse(algorithm.displayName.isEmpty, "\(algorithm) should have display name")
        }
    }
}
