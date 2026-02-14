import Foundation
import Testing
@testable import Shfl

@Suite("PlaybackState Tests")
struct PlaybackStateTests {
    @Test("Empty state has no song and is not playing")
    func emptyState() {
        let state = PlaybackState.empty
        #expect(state == .empty)
        #expect(state.currentSong == nil)
        #expect(!state.isPlaying)
    }

    @Test("Stopped state is not empty and has no song")
    func stoppedState() {
        let state = PlaybackState.stopped
        #expect(state != .empty)
        #expect(state.currentSong == nil)
        #expect(!state.isPlaying)
    }

    @Test("Playing state has a song and is playing")
    func playingState() {
        let song = Song(id: "1", title: "Test", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        let state = PlaybackState.playing(song)

        #expect(state != .empty)
        #expect(state.currentSong == song)
        #expect(state.isPlaying)
    }

    @Test("Paused state has a song but is not playing")
    func pausedState() {
        let song = Song(id: "1", title: "Test", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        let state = PlaybackState.paused(song)

        #expect(state != .empty)
        #expect(state.currentSong == song)
        #expect(!state.isPlaying)
    }

    @Test("Loading state has a song but is not playing")
    func loadingState() {
        let song = Song(id: "1", title: "Test", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        let state = PlaybackState.loading(song)

        #expect(state.currentSong == song)
        #expect(!state.isPlaying)
    }

    @Test("Error state has no song and is not playing")
    func errorState() {
        let error = NSError(domain: "test", code: 1)
        let state = PlaybackState.error(error)

        #expect(state.currentSong == nil)
        #expect(!state.isPlaying)
    }

    @Test("States with same case and song are equal")
    func stateEquality() {
        let song = Song(id: "1", title: "Test", artist: "Artist", albumTitle: "Album", artworkURL: nil)

        #expect(PlaybackState.empty == PlaybackState.empty)
        #expect(PlaybackState.stopped == PlaybackState.stopped)
        #expect(PlaybackState.playing(song) == PlaybackState.playing(song))
        #expect(PlaybackState.paused(song) == PlaybackState.paused(song))

        let song2 = Song(id: "2", title: "Other", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        #expect(PlaybackState.playing(song) != PlaybackState.playing(song2))
    }

    // MARK: - isActive Tests

    @Test("isActive returns true for playing state")
    func isActive_returnsTrue_forPlayingState() {
        let song = Song(id: "1", title: "Test", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        let state = PlaybackState.playing(song)
        #expect(state.isActive)
    }

    @Test("isActive returns true for paused state")
    func isActive_returnsTrue_forPausedState() {
        let song = Song(id: "1", title: "Test", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        let state = PlaybackState.paused(song)
        #expect(state.isActive)
    }

    @Test("isActive returns true for loading state")
    func isActive_returnsTrue_forLoadingState() {
        let song = Song(id: "1", title: "Test", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        let state = PlaybackState.loading(song)
        #expect(state.isActive)
    }

    @Test("isActive returns false for empty state")
    func isActive_returnsFalse_forEmptyState() {
        let state = PlaybackState.empty
        #expect(!state.isActive)
    }

    @Test("isActive returns false for stopped state")
    func isActive_returnsFalse_forStoppedState() {
        let state = PlaybackState.stopped
        #expect(!state.isActive)
    }

    @Test("isActive returns false for error state")
    func isActive_returnsFalse_forErrorState() {
        let state = PlaybackState.error(NSError(domain: "test", code: 1))
        #expect(!state.isActive)
    }

    // MARK: - currentSongId Tests

    @Test("currentSongId returns id for playing state")
    func currentSongId_returnsId_forPlayingState() {
        let song = Song(id: "abc123", title: "Test", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        let state = PlaybackState.playing(song)
        #expect(state.currentSongId == "abc123")
    }

    @Test("currentSongId returns nil for empty state")
    func currentSongId_returnsNil_forEmptyState() {
        let state = PlaybackState.empty
        #expect(state.currentSongId == nil)
    }

    @Test("currentSongId returns nil for stopped state")
    func currentSongId_returnsNil_forStoppedState() {
        let state = PlaybackState.stopped
        #expect(state.currentSongId == nil)
    }

    @Test("currentSongId returns id for paused state")
    func currentSongId_returnsId_forPausedState() {
        let song = Song(id: "paused123", title: "Test", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        let state = PlaybackState.paused(song)
        #expect(state.currentSongId == "paused123")
    }

    @Test("currentSongId returns id for loading state")
    func currentSongId_returnsId_forLoadingState() {
        let song = Song(id: "loading456", title: "Test", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        let state = PlaybackState.loading(song)
        #expect(state.currentSongId == "loading456")
    }

    @Test("currentSongId returns nil for error state")
    func currentSongId_returnsNil_forErrorState() {
        let state = PlaybackState.error(NSError(domain: "test", code: 1))
        #expect(state.currentSongId == nil)
    }
}
