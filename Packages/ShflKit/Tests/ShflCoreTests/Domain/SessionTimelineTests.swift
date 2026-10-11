import Foundation
import Testing
@testable import ShflCore

@Suite("Session timeline")
struct SessionTimelineTests {
    let songs = ["a", "b", "c", "d"].map {
        Song(id: $0, title: $0.uppercased(), artist: "Artist", albumTitle: "Album", artworkURL: nil)
    }
    let shuffledAt = Date(timeIntervalSince1970: 1_000)

    var session: ListeningSession {
        ListeningSession(songOrder: songs, algorithm: .noRepeat, seed: 1, shuffledAt: shuffledAt)
    }

    @Test("Splits the session around the current song")
    func splitsAroundCurrent() {
        let timeline = SessionTimeline(
            activeSession: session, currentSongID: "c", endedSession: nil, draftSongIDs: ["a", "b", "c", "d"]
        )

        #expect(timeline.status == .active)
        #expect(timeline.played.map(\.id) == ["a", "b"])
        #expect(timeline.current?.id == "c")
        #expect(timeline.upcoming.map(\.id) == ["d"])
        #expect(timeline.songs.map(\.id) == ["a", "b", "c", "d"])
        #expect(timeline.position == 3)
        #expect(timeline.songCount == 4)
        #expect(timeline.shuffledAt == shuffledAt)
    }

    @Test("A current song the session doesn't know leaves everything upcoming")
    func unknownCurrent() {
        let timeline = SessionTimeline(
            activeSession: session, currentSongID: "elsewhere", endedSession: nil, draftSongIDs: []
        )

        #expect(timeline.current == nil)
        #expect(timeline.position == nil)
        #expect(timeline.upcoming.count == 4)
    }

    @Test("Compares the draft with the session both ways")
    func draftChanges() {
        let timeline = SessionTimeline(
            activeSession: session, currentSongID: "a", endedSession: nil, draftSongIDs: ["a", "b", "new"]
        )

        #expect(timeline.joiningNextShuffle == ["new"])
        #expect(timeline.leftPool == ["c", "d"])
    }

    @Test("An ended session is all played, with when it ended")
    func ended() {
        let endedAt = Date(timeIntervalSince1970: 5_000)
        let timeline = SessionTimeline(
            activeSession: nil, currentSongID: nil, endedSession: (session, endedAt), draftSongIDs: []
        )

        #expect(timeline.status == .ended(at: endedAt))
        #expect(timeline.played.map(\.id) == ["a", "b", "c", "d"])
        #expect(timeline.current == nil)
        #expect(timeline.upcoming.isEmpty)
    }

    @Test("With no session there's nothing to show or compare")
    func idle() {
        let timeline = SessionTimeline(activeSession: nil, currentSongID: nil, endedSession: nil, draftSongIDs: ["a"])

        #expect(timeline == .idle)
        #expect(timeline.joiningNextShuffle.isEmpty)
    }
}

@Suite("Transport intents")
struct TransportIntentsTests {
    @Test("Play pauses or resumes a session, otherwise says what it will shuffle")
    func play() {
        #expect(intents(active: true, playing: true).play == .pause)
        #expect(intents(active: true, playing: false).play == .resume)
        #expect(intents(active: false, draft: 37).play == .shuffleDraft(songCount: 37))
        #expect(intents(active: false, draft: 0).play == .autofillAndShuffle(songCount: 120))
    }

    @Test("Shuffle is Again only when the draft matches what's playing")
    func shuffle() {
        #expect(intents(active: true, draft: 86).shuffle == .again)
        #expect(intents(active: true, draft: 90, differs: true).shuffle == .changedDraft(songCount: 90))
        #expect(intents(active: false, draft: 12).shuffle == .draft(songCount: 12))
        #expect(intents(active: true, draft: 0, differs: true).shuffle == .autofillAndShuffle(songCount: 120))
    }

    private func intents(active: Bool, playing: Bool = false, draft: Int = 10, differs: Bool = false) -> TransportIntents {
        TransportIntents(
            hasActiveSession: active,
            isPlaying: playing,
            draftSongCount: draft,
            autofillSongCount: 120,
            draftDiffersFromSession: differs
        )
    }
}
