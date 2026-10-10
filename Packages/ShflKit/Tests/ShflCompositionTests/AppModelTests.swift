import XCTest
@testable import ShflComposition
@testable import ShflCore
@testable import ShflDeterministic
import ShflLastFM

@MainActor
final class AppModelTests: XCTestCase {
    func testDraftEditorEditsTheLaunchesDraft() {
        let model = AppModel.preview()
        let song = DeterministicLibrary.sample.songs[0]

        let edit = model.makeDraftEditor().toggle(song)

        XCTAssertEqual(edit, .added(songCount: 1, reachedMilestone: true))
        XCTAssertEqual(model.sessionDraft.songs, [song])
    }

    func testScreensBrowseTheLaunchesLibrary() async {
        let model = AppModel.preview(library: .sample)
        let playlist = DeterministicLibrary.sample.playlists[0]

        let artistSongs = model.makeSongs(by: "Pink Floyd")
        let playlistSongs = model.makeSongs(in: playlist)
        await artistSongs.loadInitialPage()
        await playlistSongs.loadInitialPage()

        XCTAssertEqual(artistSongs.songs.map(\.title), ["Comfortably Numb", "Wish You Were Here"])
        XCTAssertEqual(playlistSongs.songs.map(\.id), ["1", "2", "3"])
    }

    func testPreviewStartsWithItsDraftAndNoAccountsOrArtwork() async {
        let draft = Array(DeterministicLibrary.sample.songs.prefix(3))

        let model = AppModel.preview(draft: draft)
        await model.lastFM.syncConnectionStatusOnly()

        XCTAssertEqual(model.sessionDraft.songs, draft)
        XCTAssertEqual(model.lastFM.connectionState, .disconnected)
        XCTAssertNil(model.artworkStore)
    }
}
