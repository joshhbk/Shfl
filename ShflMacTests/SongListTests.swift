import Foundation
import XCTest
@testable import ShflMac
import ShflComposition
import ShflCore

@MainActor
final class SongMarksTests: XCTestCase {
    func test_marksPickedOpenAndFull() {
        let songs = DeterministicSongs.make(3)
        let idle = AppModel.preview().sessionHost.timeline

        let roomy = SongMarks(pickedIDs: [songs[0].id], isFull: false, timeline: idle)
        XCTAssertEqual(roomy[songs[0]].pick, .picked)
        XCTAssertEqual(roomy[songs[1]].pick, .open)

        let full = SongMarks(pickedIDs: [songs[0].id], isFull: true, timeline: idle)
        XCTAssertEqual(full[songs[0]].pick, .picked)
        XCTAssertEqual(full[songs[1]].pick, .full)
    }

    func test_marksThePlayingSongAndSongsPickedSinceTheShuffle() async throws {
        let songs = DeterministicSongs.make(4)
        let model = AppModel.preview(draft: Array(songs.prefix(3)))
        await model.sessionHost.startFreshShuffle()
        let editor = model.makeDraftEditor()
        editor.add([songs[3]])
        let timeline = model.sessionHost.timeline
        let current = try XCTUnwrap(timeline.current)

        let marks = SongMarks(pickedIDs: Set(editor.draft.songs.map(\.id)), isFull: false, timeline: timeline)

        XCTAssertTrue(marks[current].isPlaying)
        XCTAssertFalse(marks[current].joinsNextShuffle)
        XCTAssertTrue(marks[songs[3]].joinsNextShuffle)
        XCTAssertFalse(marks[songs[3]].isPlaying)
    }
}

final class SongStatTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_GB")
        return calendar
    }()

    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 11, hour: 12))! }

    func test_followsTheSort() {
        XCTAssertEqual(SongStat(.mostPlayed), .plays)
        XCTAssertEqual(SongStat(.alphabetical), .plays)
        XCTAssertEqual(SongStat(.recentlyPlayed), .lastPlayed)
        XCTAssertEqual(SongStat(.recentlyAdded), .added)
    }

    func test_datesReadAsTodayYesterdayOrADay() {
        func song(playedDaysAgo days: Int) -> Song {
            Song(id: "1", title: "Kyoto", artist: "Phoebe Bridgers", albumTitle: "Punisher", artworkURL: nil,
                 lastPlayedDate: calendar.date(byAdding: .day, value: -days, to: now))
        }
        XCTAssertEqual(SongStat.lastPlayed.text(for: song(playedDaysAgo: 0), now: now, calendar: calendar), "Today")
        XCTAssertEqual(SongStat.lastPlayed.text(for: song(playedDaysAgo: 1), now: now, calendar: calendar), "Yesterday")
        XCTAssertFalse(SongStat.lastPlayed.text(for: song(playedDaysAgo: 8), now: now, calendar: calendar).contains("2026"))
        XCTAssertTrue(SongStat.lastPlayed.text(for: song(playedDaysAgo: 400), now: now, calendar: calendar).contains("2025"))
    }

    func test_missingDatesShowADash() {
        let song = Song(id: "1", title: "Kyoto", artist: "Phoebe Bridgers", albumTitle: "Punisher", artworkURL: nil)
        XCTAssertEqual(SongStat.lastPlayed.text(for: song, now: now, calendar: calendar), "—")
        XCTAssertEqual(SongStat.added.text(for: song, now: now, calendar: calendar), "—")
        XCTAssertEqual(SongStat.lastPlayed.spoken(for: song, now: now, calendar: calendar), "Never played.")
    }

    func test_durationsReadLikeAClock() {
        XCTAssertEqual(SongDuration.text(234), "3:54")
        XCTAssertEqual(SongDuration.text(3725), "1:02:05")
        XCTAssertEqual(SongDuration.text(nil), "")
    }
}

final class SongSpeechTests: XCTestCase {
    private let song = Song(
        id: "1", title: "Green Light", artist: "Lorde", albumTitle: "Melodrama", artworkURL: nil,
        playCount: 169, duration: 234
    )

    func test_describesAnUnpickedSong() {
        let mark = SongMark(pick: .open, isPlaying: false, joinsNextShuffle: false)
        XCTAssertEqual(
            SongSpeech.describe(song, mark: mark, stat: .plays),
            "Green Light, Lorde, Melodrama. 169 plays. \(SongDuration.spoken(234)) Not picked."
        )
        XCTAssertEqual(SongSpeech.pickActionName(for: mark), "Add to Picks")
    }

    func test_describesAPlayingPickedSongWithoutAStat() {
        let mark = SongMark(pick: .picked, isPlaying: true, joinsNextShuffle: false)
        XCTAssertEqual(
            SongSpeech.describe(song, mark: mark, stat: nil),
            "Green Light, Lorde, Melodrama. \(SongDuration.spoken(234)) Playing now. Picked."
        )
        XCTAssertEqual(SongSpeech.pickActionName(for: mark), "Remove from Picks")
    }

    func test_saysWhenASongJoinsTheNextShuffleOrPicksAreFull() {
        let joining = SongMark(pick: .picked, isPlaying: false, joinsNextShuffle: true)
        XCTAssertTrue(SongSpeech.describe(song, mark: joining, stat: nil).hasSuffix("Picked, plays from the next shuffle."))
        let full = SongMark(pick: .full, isPlaying: false, joinsNextShuffle: false)
        XCTAssertTrue(SongSpeech.describe(song, mark: full, stat: nil).hasSuffix("Not picked. Picks are full."))
    }
}

final class SongOrderTests: XCTestCase {
    private func song(_ title: String, plays: Int = 0, played: Double? = nil, added: Double? = nil) -> Song {
        Song(
            id: title, title: title, artist: "Beach House", albumTitle: "Bloom", artworkURL: nil, playCount: plays,
            lastPlayedDate: played.map(Date.init(timeIntervalSinceReferenceDate:)),
            dateAdded: added.map(Date.init(timeIntervalSinceReferenceDate:))
        )
    }

    func test_sortsLikeTheCatalog() {
        let songs = [song("Myth", plays: 5, played: 10, added: 3), song("Lazuli", plays: 9, added: 1), song("Zebra", plays: 5, played: 30)]
        XCTAssertEqual(SongOrder.sorted(songs, by: .alphabetical).map(\.title), ["Lazuli", "Myth", "Zebra"])
        XCTAssertEqual(SongOrder.sorted(songs, by: .mostPlayed).map(\.title), ["Lazuli", "Myth", "Zebra"])
        XCTAssertEqual(SongOrder.sorted(songs, by: .recentlyPlayed).map(\.title), ["Zebra", "Myth", "Lazuli"])
        XCTAssertEqual(SongOrder.sorted(songs, by: .recentlyAdded).map(\.title), ["Myth", "Lazuli", "Zebra"])
    }

    func test_countsReadNaturally() {
        XCTAssertEqual(SongCount.text(1), "1 song")
        XCTAssertEqual(SongCount.text(41), "41 songs")
    }
}
