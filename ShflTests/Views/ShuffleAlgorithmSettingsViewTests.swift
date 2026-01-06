import XCTest
import SwiftUI
@testable import Shfl

final class ShuffleAlgorithmSettingsViewTests: XCTestCase {

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "shuffleAlgorithm")
        super.tearDown()
    }

    func testDefaultAlgorithmIsNoRepeat() {
        UserDefaults.standard.removeObject(forKey: "shuffleAlgorithm")
        let raw = UserDefaults.standard.string(forKey: "shuffleAlgorithm")
        let algorithm = raw.flatMap { ShuffleAlgorithm(rawValue: $0) } ?? .noRepeat
        XCTAssertEqual(algorithm, .noRepeat)
    }

    func testAlgorithmPersistsToUserDefaults() {
        UserDefaults.standard.set(ShuffleAlgorithm.artistSpacing.rawValue, forKey: "shuffleAlgorithm")
        let raw = UserDefaults.standard.string(forKey: "shuffleAlgorithm")!
        let algorithm = ShuffleAlgorithm(rawValue: raw)
        XCTAssertEqual(algorithm, .artistSpacing)
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
