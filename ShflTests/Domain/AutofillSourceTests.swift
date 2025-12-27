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

    @Test("Excludes songs already in shuffle")
    func excludesSongsAlreadyInShuffle() async throws {
        let mockService = MockMusicService()
        let songs = (1...10).map { makeSong(id: "\($0)") }
        await mockService.setLibrarySongs(songs)

        let source = LibraryAutofillSource(musicService: mockService)
        let excluding: Set<String> = ["1", "2", "3"]
        let result = try await source.fetchSongs(excluding: excluding, limit: 10)

        // Should not contain excluded IDs
        let resultIds = Set(result.map { $0.id })
        #expect(resultIds.isDisjoint(with: excluding))
    }

    @Test("Returns empty when all songs excluded")
    func returnsEmptyWhenAllExcluded() async throws {
        let mockService = MockMusicService()
        let songs = [makeSong(id: "1"), makeSong(id: "2")]
        await mockService.setLibrarySongs(songs)

        let source = LibraryAutofillSource(musicService: mockService)
        let result = try await source.fetchSongs(excluding: ["1", "2"], limit: 10)

        #expect(result.isEmpty)
    }

    @Test("Respects the limit parameter")
    func respectsLimit() async throws {
        let mockService = MockMusicService()
        let songs = (1...100).map { makeSong(id: "\($0)") }
        await mockService.setLibrarySongs(songs)

        let source = LibraryAutofillSource(musicService: mockService)
        let result = try await source.fetchSongs(excluding: [], limit: 20)

        #expect(result.count == 20)
    }

    @Test("Returns less than limit when library is small")
    func returnsLessThanLimitWhenLibrarySmall() async throws {
        let mockService = MockMusicService()
        let songs = (1...5).map { makeSong(id: "\($0)") }
        await mockService.setLibrarySongs(songs)

        let source = LibraryAutofillSource(musicService: mockService)
        let result = try await source.fetchSongs(excluding: [], limit: 50)

        #expect(result.count == 5)
    }

    private func makeSong(id: String) -> Song {
        Song(id: id, title: "Song \(id)", artist: "Artist", albumTitle: "Album", artworkURL: nil)
    }
}
