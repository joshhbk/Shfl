import Foundation
import XCTest
@testable import ShflMac
import ShflCore

final class LibrarySongOrderTests: XCTestCase {
    func test_eachColumnStandsForItsOptionWhicheverWayItIsFlipped() {
        XCTAssertEqual(LibrarySongOrder.option(for: [KeyPathComparator(\Song.title)]), .alphabetical)
        XCTAssertEqual(LibrarySongOrder.option(for: [KeyPathComparator(\Song.title, order: .reverse)]), .alphabetical)
        XCTAssertEqual(LibrarySongOrder.option(for: [KeyPathComparator(\Song.playCount)]), .mostPlayed)
        XCTAssertEqual(LibrarySongOrder.option(for: [KeyPathComparator(\Song.playCount, order: .reverse)]), .mostPlayed)
    }

    func test_anOrderWithNoMatchingOptionChoosesNone() {
        XCTAssertNil(LibrarySongOrder.option(for: []))
        XCTAssertNil(LibrarySongOrder.option(for: [KeyPathComparator(\Song.artist)]))
    }

    func test_optionsWithAColumnRoundTrip() {
        for option in [SortOption.alphabetical, .mostPlayed] {
            XCTAssertEqual(LibrarySongOrder.option(for: LibrarySongOrder.sortOrder(for: option)), option)
        }
    }

    func test_mostPlayedSortsPlaysDescending() {
        XCTAssertEqual(LibrarySongOrder.sortOrder(for: .mostPlayed).first?.order, .reverse)
    }

    func test_optionsWithoutAColumnShowNoIndicator() {
        XCTAssertTrue(LibrarySongOrder.sortOrder(for: .recentlyPlayed).isEmpty)
        XCTAssertTrue(LibrarySongOrder.sortOrder(for: .recentlyAdded).isEmpty)
    }
}
