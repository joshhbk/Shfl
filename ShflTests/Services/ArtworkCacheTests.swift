import Foundation
import MusicKit
import Testing
@testable import Shfl

@Suite("ArtworkCache Tests")
struct ArtworkCacheTests {

    @MainActor
    @Test("setArtwork publishes update to listeners for same id")
    func setArtworkPublishesUpdate() async throws {
        let cache = ArtworkCache.makeForTesting()
        let stream = cache.artworkUpdates(for: "song-1")
        let artwork = try makeArtwork(path: "song-1")

        cache.setArtwork(artwork, for: "song-1")

        let received = await firstValue(from: stream)
        #expect(received == artwork)
    }

    @MainActor
    @Test("multiple listeners receive same artwork update")
    func multipleListenersReceiveSameUpdate() async throws {
        let cache = ArtworkCache.makeForTesting()
        let stream1 = cache.artworkUpdates(for: "song-1")
        let stream2 = cache.artworkUpdates(for: "song-1")
        let artwork = try makeArtwork(path: "shared")

        cache.setArtwork(artwork, for: "song-1")

        let received1 = await firstValue(from: stream1)
        let received2 = await firstValue(from: stream2)

        #expect(received1 == artwork)
        #expect(received2 == artwork)
    }

    @MainActor
    @Test("listeners do not receive updates for different ids")
    func listenersAreScopedById() async throws {
        let cache = ArtworkCache.makeForTesting()
        let streamA = cache.artworkUpdates(for: "song-a")
        let streamB = cache.artworkUpdates(for: "song-b")
        let artworkA = try makeArtwork(path: "a")

        cache.setArtwork(artworkA, for: "song-a")

        let receivedA = await firstValue(from: streamA)
        let receivedB = await firstValue(from: streamB, timeoutNanoseconds: 50_000_000)

        #expect(receivedA == artworkA)
        #expect(receivedB == nil)
    }

    @MainActor
    @Test("cached artwork stream yields immediately")
    func cachedArtworkStreamYieldsImmediately() async throws {
        let cache = ArtworkCache.makeForTesting()
        let artwork = try makeArtwork(path: "cached")
        cache.setArtwork(artwork, for: "song-cached")

        let stream = cache.artworkUpdates(for: "song-cached")
        let received = await firstValue(from: stream, timeoutNanoseconds: 50_000_000)

        #expect(received == artwork)
    }

    @MainActor
    private func firstValue(
        from stream: AsyncStream<Artwork>,
        timeoutNanoseconds: UInt64 = 200_000_000
    ) async -> Artwork? {
        await withTaskGroup(of: Artwork?.self) { group in
            group.addTask {
                for await artwork in stream {
                    return artwork
                }
                return nil
            }

            group.addTask {
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                return nil
            }

            let value = await group.next() ?? nil
            group.cancelAll()
            return value
        }
    }

    private func makeArtwork(path: String) throws -> Artwork {
        let json = """
        {
          "width": 100,
          "height": 100,
          "url": "https://example.com/\(path)/{w}x{h}.jpg"
        }
        """

        let data = try #require(json.data(using: .utf8))
        return try JSONDecoder().decode(Artwork.self, from: data)
    }
}
