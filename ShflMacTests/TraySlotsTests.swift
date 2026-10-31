import XCTest
@testable import ShflMac
import ShflCore

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
