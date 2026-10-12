import XCTest
@testable import ShflMac
import ShflComposition
import ShflCore
import ShflDeterministic

@MainActor
final class DraftEditingTests: XCTestCase {
    private var beeps = 0

    private func makeDrafting(draft: [Song] = []) -> DraftEditing {
        Shell(model: .preview(library: .empty, draft: draft), beep: { [unowned self] in beeps += 1 }).drafting
    }

    func test_checkingASongAddsItWithoutFeedback() {
        let drafting = makeDrafting(draft: DeterministicSongs.make(2))

        drafting.toggle(DeterministicSongs.make(1, start: 10)[0])

        XCTAssertEqual(drafting.draft.songCount, 3)
        XCTAssertNil(drafting.moment)
        XCTAssertEqual(beeps, 0)
    }

    func test_reachingAMilestoneMarksIt() {
        let drafting = makeDrafting(draft: DeterministicSongs.make(49))

        drafting.toggle(DeterministicSongs.make(1, start: 100)[0])

        XCTAssertEqual(drafting.draft.songCount, 50)
        XCTAssertEqual(drafting.moment?.kind, .milestone(50))
    }

    func test_uncheckingASongRemovesItWithoutAMoment() {
        let songs = DeterministicSongs.make(50)
        let drafting = makeDrafting(draft: songs)

        drafting.toggle(songs[0])

        XCTAssertEqual(drafting.draft.songCount, 49)
        XCTAssertNil(drafting.moment)
    }

    func test_addingToAFullDraftBeepsAndChangesNothing() {
        let drafting = makeDrafting(draft: DeterministicSongs.make(120))

        drafting.toggle(DeterministicSongs.make(1, start: 500)[0])

        XCTAssertEqual(beeps, 1)
        XCTAssertEqual(drafting.draft.songCount, drafting.draft.capacity)
        XCTAssertNil(drafting.failureMessage)
    }

    func test_addingASelectionThatDoesNotFitBeepsAndAddsNone() {
        let drafting = makeDrafting(draft: DeterministicSongs.make(119))

        drafting.add(DeterministicSongs.make(2, start: 500))

        XCTAssertEqual(beeps, 1)
        XCTAssertEqual(drafting.draft.songCount, 119)
        XCTAssertEqual(drafting.moment?.kind, .noRoom)
    }

    func test_addingASelectionPastAMilestoneMarksIt() {
        let drafting = makeDrafting(draft: DeterministicSongs.make(98))

        drafting.add(DeterministicSongs.make(3, start: 500))

        XCTAssertEqual(drafting.draft.songCount, 101)
        XCTAssertEqual(drafting.moment?.kind, .milestone(100))
    }

    func test_aSecondNoRoomIsANewMoment() {
        let drafting = makeDrafting(draft: DeterministicSongs.make(120))

        drafting.add(DeterministicSongs.make(1, start: 500))
        let first = drafting.moment
        drafting.add(DeterministicSongs.make(1, start: 600))

        XCTAssertEqual(drafting.moment?.kind, .noRoom)
        XCTAssertNotEqual(drafting.moment, first)
    }

    func test_clearAllEmptiesTheDraft() {
        let drafting = makeDrafting(draft: DeterministicSongs.make(5))

        drafting.clearAll()

        XCTAssertTrue(drafting.draft.isEmpty)
    }
}
