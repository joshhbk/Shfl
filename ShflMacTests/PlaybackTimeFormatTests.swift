import XCTest
@testable import ShflMac

final class PlaybackTimeFormatTests: XCTestCase {
    func test_formatsMinutesAndSeconds() {
        XCTAssertEqual(PlaybackTimeFormat.string(for: 0), "0:00")
        XCTAssertEqual(PlaybackTimeFormat.string(for: 75.9), "1:15")
    }

    func test_addsHoursFromAnHourOn() {
        XCTAssertEqual(PlaybackTimeFormat.string(for: 3725), "1:02:05")
    }

    func test_negativeTimesShowAsZero() {
        XCTAssertEqual(PlaybackTimeFormat.string(for: -4), "0:00")
    }
}
