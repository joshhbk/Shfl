import XCTest
@testable import ShflCore

@MainActor
final class SessionDraftEditorTests: XCTestCase {
    private func makeSongs(_ count: Int, start: Int = 1) -> [Song] {
        (start..<(start + count)).map { index in
            Song(
                id: "\(index)",
                title: "Song \(index)",
                artist: "Artist \(index)",
                albumTitle: "Album",
                artworkURL: nil
            )
        }
    }

    func test_toggleAddsToTheDraft() throws {
        let draft = SessionDraftStore()
        let editor = SessionDraftEditor()

        let edit = editor.toggle(makeSongs(1)[0], in: draft)

        XCTAssertEqual(draft.songs.map(\.id), ["1"])
        XCTAssertEqual(edit, .added(songCount: 1, reachedMilestone: true))
    }

    func test_addingReportsMilestonesOnlyAtTheirCounts() throws {
        let draft = SessionDraftStore()
        try draft.add(makeSongs(48))
        let editor = SessionDraftEditor()

        let toFortyNine = editor.toggle(makeSongs(1, start: 200)[0], in: draft)
        let toFifty = editor.toggle(makeSongs(1, start: 201)[0], in: draft)
        let toFiftyOne = editor.toggle(makeSongs(1, start: 202)[0], in: draft)

        XCTAssertEqual(toFortyNine, .added(songCount: 49, reachedMilestone: false))
        XCTAssertEqual(toFifty, .added(songCount: 50, reachedMilestone: true))
        XCTAssertEqual(toFiftyOne, .added(songCount: 51, reachedMilestone: false))
    }

    func test_fillingTheDraftIsAMilestone() throws {
        let draft = SessionDraftStore()
        try draft.add(makeSongs(SessionDraft.maxSongs - 1))
        let editor = SessionDraftEditor()

        let edit = editor.toggle(makeSongs(1, start: 500)[0], in: draft)

        XCTAssertEqual(edit, .added(songCount: SessionDraft.maxSongs, reachedMilestone: true))
    }

    func test_toggleRemovesFromTheDraft() throws {
        let draft = SessionDraftStore()
        try draft.add(makeSongs(2))
        let editor = SessionDraftEditor()

        let edit = editor.toggle(makeSongs(1)[0], in: draft)

        XCTAssertEqual(draft.songs.map(\.id), ["2"])
        XCTAssertEqual(edit, .removed)
    }

    func test_toggleAtCapacityLeavesTheDraftAlone() throws {
        let draft = SessionDraftStore()
        try draft.add(makeSongs(SessionDraft.maxSongs))
        let editor = SessionDraftEditor()

        let edit = editor.toggle(makeSongs(1, start: 500)[0], in: draft)

        XCTAssertEqual(draft.songCount, SessionDraft.maxSongs)
        XCTAssertEqual(edit, .rejectedAtCapacity)
        XCTAssertNil(editor.actionErrorMessage)
    }

    func test_clearAllEmptiesTheDraft() throws {
        let draft = SessionDraftStore()
        try draft.add(makeSongs(3))
        let editor = SessionDraftEditor()

        editor.clearAll(in: draft)

        XCTAssertTrue(draft.isEmpty)
    }

    // MARK: - Autofill exhaustion

    func test_autofillThatCameBackShortWithRoomLeftIsExhausted() throws {
        let draft = SessionDraftStore()
        let editor = SessionDraftEditor()

        editor.noteAutofillCompleted(addedCount: 3, requestedCount: 5, remainingCapacity: 2)
        XCTAssertTrue(editor.autofillIsExhausted)

        // A later edit clears the exhausted flag.
        editor.toggle(makeSongs(1, start: 50)[0], in: draft)
        XCTAssertFalse(editor.autofillIsExhausted)
    }

    func test_autofillThatFilledTheRoomIsNotExhausted() {
        let editor = SessionDraftEditor()

        editor.noteAutofillCompleted(addedCount: 1, requestedCount: 1, remainingCapacity: 0)

        XCTAssertFalse(editor.autofillIsExhausted)
    }
}
