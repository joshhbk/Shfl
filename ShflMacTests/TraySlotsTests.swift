import XCTest
@testable import ShflMac
import ShflCore

@MainActor
final class TraySlotsTests: XCTestCase {
    private let milestones: Set<Int> = [1, 50, 100, 120]

    func test_anEmptyTrayOutlinesEveryMilestoneSlot() {
        let slots = TraySlots(picks: [], capacity: 120, milestones: milestones, joiningNextShuffle: [])

        let outlined = slots.slots.indices.filter { slots[$0] == .empty(isMilestone: true) }
        XCTAssertEqual(outlined, [0, 49, 99, 119])
    }

    func test_picksFillFromTheStartAndRingOnlyThoseJoiningTheNextShuffle() {
        let songs = DeterministicSongs.make(3)
        let slots = TraySlots(picks: songs, capacity: 120, milestones: milestones, joiningNextShuffle: [songs[2].id])

        XCTAssertEqual(slots[0], .picked(songs[0], joinsNextShuffle: false))
        XCTAssertEqual(slots[2], .picked(songs[2], joinsNextShuffle: true))
        XCTAssertEqual(slots[3], .empty(isMilestone: false))
        XCTAssertEqual(slots[49], .empty(isMilestone: true))
        XCTAssertEqual(slots.slots.count, 120)
    }
}

@MainActor
final class TrayMotionTests: XCTestCase {
    func test_fiftyRipplesItsRowLeftToRight() {
        var motion = TrayMotion()
        motion.play(.milestone(50))

        XCTAssertEqual(motion.pulseDelay(for: 40, capacity: 120, columns: 10), 0)
        XCTAssertEqual(motion.pulseDelay(for: 49, capacity: 120, columns: 10), 9 * TrayMotion.rippleStep)
        XCTAssertNil(motion.pulseDelay(for: 39, capacity: 120, columns: 10))
        XCTAssertEqual(motion.milestoneBeats, 1)
    }

    func test_theFirstPickAndAFullTrayPulseTogether() {
        var motion = TrayMotion()
        motion.play(.milestone(1))
        XCTAssertEqual(motion.pulseDelay(for: 0, capacity: 120, columns: 10), 0)
        XCTAssertNil(motion.pulseDelay(for: 1, capacity: 120, columns: 10))

        motion.play(.milestone(120))
        XCTAssertEqual(motion.pulseDelay(for: 7, capacity: 120, columns: 10), 0)
        XCTAssertEqual(motion.pulseDelay(for: 119, capacity: 120, columns: 10), 0)
    }

    func test_noRoomOnlyFlashesTheSlots() {
        var motion = TrayMotion()
        motion.play(.noRoom)

        XCTAssertEqual(motion.noRoomFlashes, 1)
        XCTAssertEqual(motion.milestoneBeats, 0)
    }
}

@MainActor
final class TrayCursorTests: XCTestCase {
    func test_startsOnTheNewestPick() {
        XCTAssertEqual(TrayCursor(count: 37)?.index, 36)
        XCTAssertNil(TrayCursor(count: 0))
    }

    func test_movesATileOrARowAndStopsAtTheEdges() throws {
        var cursor = try XCTUnwrap(TrayCursor(count: 37))

        cursor.move(.up, count: 37, columns: 10)
        XCTAssertEqual(cursor.index, 26)
        cursor.move(.left, count: 37, columns: 10)
        XCTAssertEqual(cursor.index, 25)
        cursor.move(.down, count: 37, columns: 10)
        XCTAssertEqual(cursor.index, 35)
        cursor.move(.down, count: 37, columns: 10)
        XCTAssertEqual(cursor.index, 35, "Nothing picked below")
        cursor.move(.right, count: 37, columns: 10)
        cursor.move(.right, count: 37, columns: 10)
        XCTAssertEqual(cursor.index, 36, "Stops at the newest pick")
    }

    func test_staysOnAPickAfterARemoval() throws {
        let cursor = try XCTUnwrap(TrayCursor(count: 3))

        XCTAssertEqual(cursor.clamped(to: 2)?.index, 1)
        XCTAssertNil(cursor.clamped(to: 0))
    }
}
