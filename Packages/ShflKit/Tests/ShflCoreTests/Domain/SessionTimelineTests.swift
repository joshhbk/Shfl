import Foundation
import Testing
@testable import ShflCore

@Suite("Session timeline")
struct SessionTimelineTests {
    let songs = ["a", "b", "c", "d"].map {
        Song(id: $0, title: $0.uppercased(), artist: "Artist", albumTitle: "Album", artworkURL: nil)
    }

    var session: ListeningSession {
        ListeningSession(songOrder: songs, algorithm: .noRepeat, seed: 1)
    }

    @Test("Splits the session around the current song")
    func splitsAroundCurrent() {
        let timeline = SessionTimeline(
            phase: .active(session), currentSongID: "c", draftSongIDs: ["a", "b", "c", "d"]
        )

        #expect(timeline.status == .active)
        #expect(timeline.played.map(\.id) == ["a", "b"])
        #expect(timeline.current?.id == "c")
        #expect(timeline.upcoming.map(\.id) == ["d"])
        #expect(timeline.songs.map(\.id) == ["a", "b", "c", "d"])
        #expect(timeline.position == 3)
        #expect(timeline.songCount == 4)
    }

    @Test("A current song the session doesn't know leaves everything upcoming")
    func unknownCurrent() {
        let timeline = SessionTimeline(
            phase: .active(session), currentSongID: "elsewhere", draftSongIDs: []
        )

        #expect(timeline.current == nil)
        #expect(timeline.position == nil)
        #expect(timeline.upcoming.count == 4)
    }

    @Test("Compares the draft with the session both ways")
    func draftChanges() {
        let timeline = SessionTimeline(
            phase: .active(session), currentSongID: "a", draftSongIDs: ["a", "b", "new"]
        )

        #expect(timeline.joiningNextShuffle == ["new"])
        #expect(timeline.leftPool == ["c", "d"])
    }

    @Test("An ended session is all played")
    func ended() {
        let timeline = SessionTimeline(phase: .ended(session), currentSongID: nil, draftSongIDs: [])

        #expect(timeline.status == .ended)
        #expect(timeline.played.map(\.id) == ["a", "b", "c", "d"])
        #expect(timeline.current == nil)
        #expect(timeline.upcoming.isEmpty)
    }

    @Test("With no session there's nothing to show or compare")
    func idle() {
        let timeline = SessionTimeline(phase: .none, currentSongID: nil, draftSongIDs: ["a"])

        #expect(timeline == .idle)
        #expect(timeline.joiningNextShuffle.isEmpty)
    }
}

@Suite("Transport intents")
struct TransportIntentsTests {
    @Test("Play pauses or resumes a session, otherwise says what it will shuffle")
    func play() {
        #expect(intents(.active(isPlaying: true, draftDiffers: false)).play == .pause)
        #expect(intents(.active(isPlaying: false, draftDiffers: false)).play == .resume)
        #expect(intents(.none, draft: 37).play == .shuffleDraft(songCount: 37))
        #expect(intents(.none, draft: 0).play == .autofillAndShuffle(songCount: 120))
    }

    @Test("Shuffle is Again only when the draft matches what's playing")
    func shuffle() {
        #expect(intents(.active(isPlaying: true, draftDiffers: false), draft: 86).shuffle == .again)
        #expect(intents(.active(isPlaying: true, draftDiffers: true), draft: 90).shuffle == .changedDraft(songCount: 90))
        #expect(intents(.none, draft: 12).shuffle == .draft(songCount: 12))
        #expect(intents(.active(isPlaying: false, draftDiffers: true), draft: 0).shuffle == .autofillAndShuffle(songCount: 120))
    }

    private func intents(_ session: TransportIntents.SessionState, draft: Int = 10) -> TransportIntents {
        TransportIntents(session: session, draftSongCount: draft, autofillSongCount: 120)
    }
}
