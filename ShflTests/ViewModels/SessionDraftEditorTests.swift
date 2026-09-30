import XCTest
@testable import Shfl

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

    func test_toggleAddsToTheDraftAndOffersUndo() throws {
        let draft = SessionDraftStore()
        let editor = SessionDraftEditor()

        editor.toggle(makeSongs(1)[0], in: draft)

        XCTAssertEqual(draft.songs.map(\.id), ["1"])
        XCTAssertEqual(editor.undoState?.action, .added)
    }

    func test_toggleRemovesFromTheDraftAndOffersUndo() throws {
        let draft = SessionDraftStore()
        try draft.add(makeSongs(2))
        let editor = SessionDraftEditor()

        editor.toggle(makeSongs(1)[0], in: draft)

        XCTAssertEqual(draft.songs.map(\.id), ["2"])
        XCTAssertEqual(editor.undoState?.action, .removed)
    }

    func test_toggleAtCapacityLeavesTheDraftAndUndoAlone() throws {
        let draft = SessionDraftStore()
        try draft.add(makeSongs(SessionDraft.maxSongs))
        let editor = SessionDraftEditor()

        editor.toggle(makeSongs(1, start: 500)[0], in: draft)

        XCTAssertEqual(draft.songCount, SessionDraft.maxSongs)
        XCTAssertNil(editor.undoState)
        XCTAssertNil(editor.actionErrorMessage)
    }

    func test_undoingAnAddRemovesTheSong() throws {
        let draft = SessionDraftStore()
        let editor = SessionDraftEditor()
        editor.toggle(makeSongs(1)[0], in: draft)
        let undoState = try XCTUnwrap(editor.undoState)

        editor.undo(undoState, in: draft)

        XCTAssertTrue(draft.isEmpty)
        XCTAssertNil(editor.undoState)
    }

    func test_undoingARemoveRestoresTheSong() throws {
        let draft = SessionDraftStore()
        try draft.add(makeSongs(1))
        let editor = SessionDraftEditor()
        editor.toggle(makeSongs(1)[0], in: draft)
        let undoState = try XCTUnwrap(editor.undoState)

        editor.undo(undoState, in: draft)

        XCTAssertEqual(draft.songs.map(\.id), ["1"])
    }

    func test_clearAllEmptiesTheDraftAndDismissesUndo() throws {
        let draft = SessionDraftStore()
        try draft.add(makeSongs(3))
        let editor = SessionDraftEditor()
        editor.toggle(makeSongs(1, start: 10)[0], in: draft)
        XCTAssertNotNil(editor.undoState)

        editor.clearAll(in: draft)

        XCTAssertTrue(draft.isEmpty)
        XCTAssertNil(editor.undoState)
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
