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

    private func makeEditor(
        player: ShufflePlayer,
        addSongs: @escaping @MainActor ([Song]) async throws -> Void = { _ in },
        removeSong: @escaping @MainActor (String) async -> Void = { _ in },
        removeAllSongs: @escaping @MainActor () async -> Void = {}
    ) -> SessionDraftEditor {
        SessionDraftEditor(
            player: player,
            addSongs: addSongs,
            removeSong: removeSong,
            removeAllSongs: removeAllSongs
        )
    }

    // MARK: - Membership is derived from the draft

    func test_selectedSongIdsReflectsTheDraft() async throws {
        let player = ShufflePlayer(playbackTransport: DeterministicMusicService())
        try player.seedSongs(makeSongs(3))
        let editor = makeEditor(player: player)

        XCTAssertEqual(editor.selectedSongIds, ["1", "2", "3"])
        XCTAssertEqual(editor.songCount, 3)
        XCTAssertTrue(editor.contains("2"))
        XCTAssertFalse(editor.contains("99"))
    }

    func test_toggleAddsThroughTheWritePortAndMembershipFollows() async throws {
        let player = ShufflePlayer(playbackTransport: DeterministicMusicService())
        let editor = makeEditor(player: player, addSongs: { songs in
            try player.seedSongs(songs)
        })

        editor.toggle(makeSongs(1)[0])
        await waitUntil { editor.selectedSongIds == ["1"] }

        XCTAssertEqual(player.allSongs.map(\.id), ["1"])
        XCTAssertEqual(editor.undoState?.action, .added)
    }

    func test_toggleRemovesThroughTheWritePortAndMembershipFollows() async throws {
        let player = ShufflePlayer(playbackTransport: DeterministicMusicService())
        try player.seedSongs(makeSongs(2))
        let editor = makeEditor(player: player, removeSong: { id in
            await player.removeSong(id: id)
        })

        editor.toggle(makeSongs(1)[0])
        await waitUntil { editor.selectedSongIds == ["2"] }

        XCTAssertEqual(player.allSongs.map(\.id), ["2"])
        XCTAssertEqual(editor.undoState?.action, .removed)
    }

    func test_undoingAnAddRemovesTheSong() async throws {
        let player = ShufflePlayer(playbackTransport: DeterministicMusicService())
        let editor = makeEditor(
            player: player,
            addSongs: { try player.seedSongs($0) },
            removeSong: { await player.removeSong(id: $0) }
        )

        editor.toggle(makeSongs(1)[0])
        await waitUntil { editor.selectedSongIds == ["1"] }
        let undoState = try XCTUnwrap(editor.undoState)

        editor.undo(undoState)
        await waitUntil { editor.selectedSongIds.isEmpty }

        XCTAssertTrue(player.allSongs.isEmpty)
        XCTAssertNil(editor.undoState)
    }

    func test_undoingARemoveRestoresTheSong() async throws {
        let player = ShufflePlayer(playbackTransport: DeterministicMusicService())
        try player.seedSongs(makeSongs(1))
        let editor = makeEditor(
            player: player,
            addSongs: { try player.seedSongs($0) },
            removeSong: { await player.removeSong(id: $0) }
        )

        editor.toggle(makeSongs(1)[0])
        await waitUntil { editor.selectedSongIds.isEmpty }
        let undoState = try XCTUnwrap(editor.undoState)

        editor.undo(undoState)
        await waitUntil { editor.selectedSongIds == ["1"] }

        XCTAssertEqual(player.allSongs.map(\.id), ["1"])
    }

    func test_clearAllRemovesEverySongAndDismissesUndo() async throws {
        let player = ShufflePlayer(playbackTransport: DeterministicMusicService())
        try player.seedSongs(makeSongs(3))
        let editor = makeEditor(
            player: player,
            addSongs: { try player.seedSongs($0) },
            removeAllSongs: { await player.removeAllSongs() }
        )

        // Seed an undo state so we can assert clearAll dismisses it.
        editor.toggle(makeSongs(1, start: 10)[0])
        await waitUntil { editor.undoState != nil }

        editor.clearAll()
        await waitUntil { editor.selectedSongIds.isEmpty }

        XCTAssertTrue(player.allSongs.isEmpty)
        XCTAssertNil(editor.undoState)
    }

    // MARK: - Capacity

    func test_capacityIsDerivedFromTheDraft() async throws {
        let player = ShufflePlayer(playbackTransport: DeterministicMusicService())
        try player.seedSongs(makeSongs(2))
        let editor = makeEditor(player: player)

        XCTAssertEqual(editor.capacity, SessionDraft.maxSongs)
        XCTAssertEqual(editor.remainingCapacity, SessionDraft.maxSongs - 2)
        XCTAssertFalse(editor.isAtCapacity)
    }

    func test_isAtCapacityWhenTheDraftIsFull() async throws {
        let player = ShufflePlayer(playbackTransport: DeterministicMusicService())
        try player.seedSongs(makeSongs(SessionDraft.maxSongs))
        let editor = makeEditor(player: player)

        XCTAssertEqual(editor.remainingCapacity, 0)
        XCTAssertTrue(editor.isAtCapacity)
    }

    // MARK: - Autofill exhaustion

    func test_autofillExhaustionTracksRemainingCapacity() async throws {
        let player = ShufflePlayer(playbackTransport: DeterministicMusicService())
        try player.seedSongs(makeSongs(2))
        let editor = makeEditor(player: player)

        // Asked for more than the library could supply, room still remains.
        editor.noteAutofillCompleted(addedCount: 3, requestedCount: 5)
        XCTAssertTrue(editor.autofillIsExhausted)

        // A later edit clears the exhausted flag.
        editor.toggle(makeSongs(1, start: 50)[0])
        XCTAssertFalse(editor.autofillIsExhausted)
    }

    func test_autofillWithRoomFilledIsNotExhausted() async throws {
        let player = ShufflePlayer(playbackTransport: DeterministicMusicService())
        try player.seedSongs(makeSongs(SessionDraft.maxSongs - 1))
        let editor = makeEditor(player: player)

        editor.noteAutofillCompleted(addedCount: 1, requestedCount: 1)
        XCTAssertFalse(editor.autofillIsExhausted)
    }
}