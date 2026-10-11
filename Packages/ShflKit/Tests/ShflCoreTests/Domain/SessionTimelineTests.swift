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

    func draft(_ ids: String..., algorithm: ShuffleAlgorithm = .noRepeat) -> SessionDraft {
        let pool = ids.map { id in
            songs.first { $0.id == id } ?? Song(id: id, title: id, artist: "Artist", albumTitle: "Album", artworkURL: nil)
        }
        return SessionDraft(songs: pool, algorithm: algorithm)
    }

    @Test("Splits the session around the current song")
    func splitsAroundCurrent() {
        let timeline = SessionTimeline(
            phase: .active(session), currentSongID: "c", draft: draft("a", "b", "c", "d")
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
            phase: .active(session), currentSongID: "elsewhere", draft: draft()
        )

        #expect(timeline.current == nil)
        #expect(timeline.position == nil)
        #expect(timeline.upcoming.count == 4)
    }

    @Test("Compares the draft with the session both ways")
    func draftChanges() {
        let timeline = SessionTimeline(
            phase: .active(session), currentSongID: "a", draft: draft("a", "b", "new")
        )

        #expect(timeline.changes.joiningNextShuffle == ["new"])
        #expect(timeline.changes.leftPool == ["c", "d"])
        #expect(!timeline.changes.algorithmChanged)
    }

    @Test("A new shuffle style alone counts as a change")
    func algorithmChange() {
        let timeline = SessionTimeline(
            phase: .active(session), currentSongID: "a", draft: draft("a", "b", "c", "d", algorithm: .artistSpacing)
        )

        #expect(timeline.changes.joiningNextShuffle.isEmpty)
        #expect(timeline.changes.leftPool.isEmpty)
        #expect(!timeline.changes.isEmpty)
    }

    @Test("An ended session is all played")
    func ended() {
        let timeline = SessionTimeline(phase: .ended(session), currentSongID: nil, draft: draft())

        #expect(timeline.status == .ended)
        #expect(timeline.played.map(\.id) == ["a", "b", "c", "d"])
        #expect(timeline.current == nil)
        #expect(timeline.upcoming.isEmpty)
    }

    @Test("With no session there's nothing to show or compare")
    func idle() {
        let timeline = SessionTimeline(phase: .none, currentSongID: nil, draft: draft("a"))

        #expect(timeline == .idle)
    }
}

@Suite("Transport intents")
struct TransportIntentsTests {
    @Test("Play pauses or resumes a session, otherwise says what it will shuffle")
    func play() {
        #expect(intents(.active(isPlaying: true, pending: .none)).play == .pause)
        #expect(intents(.active(isPlaying: false, pending: .none)).play == .resume)
        #expect(intents(.none, draft: 37).play == .shuffleDraft(songCount: 37))
        #expect(intents(.none, draft: 0).play == .autofillAndShuffle(songCount: 120))
    }

    @Test("Shuffle is Again only when the draft matches what's playing")
    func shuffle() {
        #expect(intents(.active(isPlaying: true, pending: .none), draft: 86).shuffle == .again)
        #expect(intents(.active(isPlaying: true, pending: .songs), draft: 90).shuffle == .changedDraft(songCount: 90))
        #expect(intents(.active(isPlaying: true, pending: .style(playing: .artistSpacing)), draft: 86).shuffle
            == .changedStyle(playing: .artistSpacing))
        #expect(intents(.none, draft: 12).shuffle == .draft(songCount: 12))
        #expect(intents(.active(isPlaying: false, pending: .songs), draft: 0).shuffle == .autofillAndShuffle(songCount: 120))
    }

    private func intents(_ session: TransportIntents.SessionState, draft: Int = 10) -> TransportIntents {
        TransportIntents(session: session, draftSongCount: draft, autofillSongCount: 120)
    }
}
