import Foundation
import Testing
@testable import Shfl

@Suite("SongUndoManager Tests")
@MainActor
struct SongUndoManagerTests {
    @Test("recordAction sets currentState with action and song")
    func testRecordAction() {
        let undoManager = SongUndoManager()
        let song = Song(id: "1", title: "Test", artist: "Artist", albumTitle: "Album", artworkURL: nil)

        undoManager.recordAction(.added, song: song)

        #expect(undoManager.currentState != nil)
        #expect(undoManager.currentState?.action == .added)
        #expect(undoManager.currentState?.song.id == "1")
    }

    @Test("currentState auto-disappears after timeout")
    func testAutoDisappearAfterTimeout() async throws {
        let undoManager = SongUndoManager()
        let song = Song(id: "1", title: "Test", artist: "Artist", albumTitle: "Album", artworkURL: nil)

        // Use longer delays for CI reliability
        undoManager.recordAction(.added, song: song, autoHideDelay: 0.3)

        #expect(undoManager.currentState != nil)

        // Wait significantly longer than the delay to account for CI scheduling delays
        try await Task.sleep(nanoseconds: 600_000_000) // 0.6 seconds

        #expect(undoManager.currentState == nil)
    }

    @Test("new action replaces old action")
    func testNewActionReplacesOld() {
        let undoManager = SongUndoManager()
        let song1 = Song(id: "1", title: "Song 1", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        let song2 = Song(id: "2", title: "Song 2", artist: "Artist", albumTitle: "Album", artworkURL: nil)

        undoManager.recordAction(.added, song: song1)
        undoManager.recordAction(.removed, song: song2)

        #expect(undoManager.currentState?.song.id == "2")
        #expect(undoManager.currentState?.action == .removed)
    }

    @Test("dismiss clears currentState")
    func testDismiss() {
        let undoManager = SongUndoManager()
        let song = Song(id: "1", title: "Test", artist: "Artist", albumTitle: "Album", artworkURL: nil)

        undoManager.recordAction(.added, song: song)
        undoManager.dismiss()

        #expect(undoManager.currentState == nil)
    }

    @Test("new action cancels previous auto-hide timer")
    func testNewActionCancelsPreviousTimer() async throws {
        let undoManager = SongUndoManager()
        let song1 = Song(id: "1", title: "Song 1", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        let song2 = Song(id: "2", title: "Song 2", artist: "Artist", albumTitle: "Album", artworkURL: nil)

        // Record first action with short delay
        undoManager.recordAction(.added, song: song1, autoHideDelay: 0.1)

        // Wait a bit, then record second action with longer delay
        try await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds
        undoManager.recordAction(.removed, song: song2, autoHideDelay: 0.3)

        // Wait past original timeout but before new timeout
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        // Should still show second action (first timer was cancelled)
        #expect(undoManager.currentState != nil)
        #expect(undoManager.currentState?.song.id == "2")
    }
}
