import Foundation
import Testing
@testable import Shfl

@Suite("UndoPill Tests")
struct UndoPillTests {
    @Test("Added action shows 'Added to Shfl' message")
    func testAddedMessage() {
        let message = UndoPill.message(for: .added, songTitle: "Bohemian Rhapsody")
        #expect(message == "Added to Shfl")
    }

    @Test("Removed action shows 'Removed' message")
    func testRemovedMessage() {
        let message = UndoPill.message(for: .removed, songTitle: "Stairway to Heaven")
        #expect(message == "Removed")
    }

    @Test("UndoState initializes with current timestamp")
    func testUndoStateInitialization() {
        let song = Song(
            id: "1",
            title: "Test Song",
            artist: "Test Artist",
            albumTitle: "Test Album",
            artworkURL: nil
        )
        let before = Date()
        let state = UndoState(action: .added, song: song)
        let after = Date()

        #expect(state.action == .added)
        #expect(state.song == song)
        #expect(state.timestamp >= before)
        #expect(state.timestamp <= after)
    }

    @Test("UndoState with different actions are not equal")
    func testUndoStateEquality() {
        let song1 = Song(
            id: "1",
            title: "Test Song",
            artist: "Test Artist",
            albumTitle: "Test Album",
            artworkURL: nil
        )
        let song2 = Song(
            id: "2",
            title: "Different Song",
            artist: "Different Artist",
            albumTitle: "Different Album",
            artworkURL: nil
        )

        let state1 = UndoState(action: .added, song: song1)
        let state2 = UndoState(action: .removed, song: song1)
        let state3 = UndoState(action: .added, song: song2)

        // States with different actions or different songs are not equal
        #expect(state1 != state2)
        #expect(state1 != state3)
    }
}
