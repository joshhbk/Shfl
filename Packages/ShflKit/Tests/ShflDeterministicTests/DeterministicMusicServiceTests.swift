import Foundation
import Testing
@testable import ShflCore
@testable import ShflDeterministic

@Suite("DeterministicMusicService Tests")
struct DeterministicMusicServiceTests {
    @Test("A library fixture is what the catalog serves")
    func servesTheLibraryFixture() async throws {
        let service = DeterministicMusicService(library: .sample)

        let firstPage = try await service.fetchLibrarySongs(sortedBy: .recentlyAdded, limit: 4, offset: 0)
        let lastPage = try await service.fetchLibrarySongs(sortedBy: .recentlyAdded, limit: 4, offset: 8)
        let playlist = try await service.fetchSongs(byPlaylistId: "p2", limit: 10, offset: 0)

        #expect(firstPage.songs.map(\.id) == ["1", "2", "3", "4"])
        #expect(firstPage.hasMore)
        #expect(lastPage.songs.map(\.id) == ["9", "10"])
        #expect(!lastPage.hasMore)
        #expect(playlist.songs.map(\.id) == ["4", "5", "6"])
    }

    @Test("Most played sorts by play count")
    func sortsByPlayCount() async throws {
        let service = DeterministicMusicService(library: .launch)

        let page = try await service.fetchLibrarySongs(sortedBy: .mostPlayed, limit: 10, offset: 0)

        #expect(page.songs.map(\.title) == ["Afterglow", "Second Wind", "Low Tide"])
    }

    @Test("Playback starts where the fixture puts it and holds still")
    @MainActor
    func playbackFixtureHoldsStill() async {
        let song = DeterministicLibrary.launch.songs[1]
        let service = DeterministicMusicService(
            library: .launch,
            playback: DeterministicPlayback(state: .paused(song), time: 78, duration: 242)
        )

        var events = service.playbackEvents.makeAsyncIterator()
        let first = await events.next()

        #expect(first == .stateChanged(.paused(song)))
        #expect(service.currentPlaybackTime == 78)
        #expect(service.currentSongDuration == 242)
        #expect(service.currentSongId == song.id)
    }

    @Test("Playing past the last song ends the session without wrapping")
    @MainActor
    func advancingPastTheEndEndsTheSession() async throws {
        let songs = DeterministicLibrary.launch.songs
        let service = DeterministicMusicService(library: .launch)
        try await service.load(
            PlaybackLoadRequest(
                sessionID: UUID(),
                queue: songs,
                currentSongID: songs[2].id,
                playbackPosition: 170,
                autoplay: true
            )
        )

        var events = service.playbackEvents.makeAsyncIterator()
        #expect(await events.next() == .stateChanged(.playing(songs[2])))

        await service.advance(by: 20)

        #expect(await events.next() == .sessionEnded)
        #expect(service.currentSongId == nil)
    }
}
