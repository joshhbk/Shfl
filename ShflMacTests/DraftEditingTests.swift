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
        XCTAssertEqual(drafting.milestonePulses, 0)
        XCTAssertEqual(beeps, 0)
    }

    func test_reachingAMilestonePulsesTheMeter() {
        let drafting = makeDrafting(draft: DeterministicSongs.make(49))

        drafting.toggle(DeterministicSongs.make(1, start: 100)[0])

        XCTAssertEqual(drafting.draft.songCount, 50)
        XCTAssertEqual(drafting.milestonePulses, 1)
    }

    func test_uncheckingASongRemovesItWithoutAPulse() {
        let songs = DeterministicSongs.make(50)
        let drafting = makeDrafting(draft: songs)

        drafting.toggle(songs[0])

        XCTAssertEqual(drafting.draft.songCount, 49)
        XCTAssertEqual(drafting.milestonePulses, 0)
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
    }

    func test_addingASelectionPastAMilestonePulsesOnce() {
        let drafting = makeDrafting(draft: DeterministicSongs.make(98))

        drafting.add(DeterministicSongs.make(3, start: 500))

        XCTAssertEqual(drafting.draft.songCount, 101)
        XCTAssertEqual(drafting.milestonePulses, 1)
    }

    func test_clearAllEmptiesTheDraft() {
        let drafting = makeDrafting(draft: DeterministicSongs.make(5))

        drafting.clearAll()

        XCTAssertTrue(drafting.draft.isEmpty)
    }
}
