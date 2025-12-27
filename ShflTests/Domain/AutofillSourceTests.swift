import Foundation
import Testing
@testable import Shfl

@Suite("AutofillSource Protocol Tests")
struct AutofillSourceTests {
    @Test("Protocol exists and can be referenced")
    func protocolExists() {
        // This test verifies the protocol compiles and can be used as a type
        let _: (any AutofillSource)? = nil
    }
}

@Suite("LibraryAutofillSource Tests")
struct LibraryAutofillSourceTests {
    @Test("Fetches songs from library up to limit")
    func fetchesSongsFromLibrary() async throws {
        let mockService = MockMusicService()
        let songs = (1...10).map { makeSong(id: "\($0)") }
        await mockService.setLibrarySongs(songs)

        let source = LibraryAutofillSource(musicService: mockService)
        let result = try await source.fetchSongs(excluding: [], limit: 5)

        #expect(result.count == 5)
    }

    private func makeSong(id: String) -> Song {
        Song(id: id, title: "Song \(id)", artist: "Artist", albumTitle: "Album", artworkURL: nil)
    }
}
