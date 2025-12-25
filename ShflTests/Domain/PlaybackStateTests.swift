import Foundation
import Testing
@testable import Shfl

@Suite("PlaybackState Tests")
struct PlaybackStateTests {
    @Test("Empty state has no song and is not playing")
    func emptyState() {
        let state = PlaybackState.empty
        #expect(state.isEmpty)
        #expect(state.currentSong == nil)
        #expect(!state.isPlaying)
    }

    @Test("Stopped state is not empty and has no song")
    func stoppedState() {
        let state = PlaybackState.stopped
        #expect(!state.isEmpty)
        #expect(state.currentSong == nil)
        #expect(!state.isPlaying)
    }

    @Test("Playing state has a song and is playing")
    func playingState() {
        let song = Song(id: "1", title: "Test", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        let state = PlaybackState.playing(song)

        #expect(!state.isEmpty)
        #expect(state.currentSong == song)
        #expect(state.isPlaying)
    }

    @Test("Paused state has a song but is not playing")
    func pausedState() {
        let song = Song(id: "1", title: "Test", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        let state = PlaybackState.paused(song)

        #expect(!state.isEmpty)
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
}
