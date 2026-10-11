import XCTest
@testable import ShflMac
import ShflComposition
import ShflCore

@MainActor
final class SessionCopyTests: XCTestCase {
    func test_idleCopySaysWhatPlayWillDo() {
        let host = AppModel.preview().sessionHost
        let copy = SessionCopy(timeline: host.timeline, play: host.intents.play)
        XCTAssertEqual(copy.title, "Just press Play")
        XCTAssertTrue(copy.subtitle.contains("fills them with 120 random songs"))
    }

    func test_activeCopyNamesTheSongThatsPlaying() async {
        let model = AppModel.preview(draft: DeterministicSongs.make(3))
        await model.sessionHost.startFreshShuffle()
        let host = model.sessionHost
        let copy = SessionCopy(timeline: host.timeline, play: host.intents.play)
        XCTAssertEqual(copy.title, host.timeline.current?.title)
        XCTAssertEqual(copy.subtitle, host.timeline.current?.byline)
    }
}

@MainActor
final class MenuBarPicksSummaryTests: XCTestCase {
    func test_summaryNamesSongChangesOrANewStyle() async throws {
        let model = AppModel.preview(draft: DeterministicSongs.make(3))
        await model.sessionHost.startFreshShuffle()
        XCTAssertNil(MenuBarPicks.summary(of: model.sessionHost.timeline.changes))

        let other = ShuffleAlgorithm.allCases.first { $0 != model.sessionDraft.algorithm }!
        model.sessionDraft.stage(other)
        XCTAssertEqual(MenuBarPicks.summary(of: model.sessionHost.timeline.changes), "New shuffle style")
    }
}
