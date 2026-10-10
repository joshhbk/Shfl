import Foundation
import MusicKit
import Testing
@testable import Shfl

@Suite("ArtworkStore Tests")
@MainActor
struct ArtworkStoreTests {

    @Test("returns the artwork the library found for a subject")
    func returnsLoadedArtwork() async throws {
        let artwork = try makeArtwork(path: "song-1")
        let library = FakeArtworkLibrary(artwork: [.song(id: "song-1"): artwork])
        let store = library.makeStore()

        let received = await store.artwork(for: .song(id: "song-1"))

        #expect(received == artwork)
    }

    @Test("callers waiting on the same subject share one lookup")
    func concurrentCallersShareOneLookup() async throws {
        let artwork = try makeArtwork(path: "shared")
        let library = FakeArtworkLibrary(artwork: [.song(id: "song-1"): artwork])
        let store = library.makeStore()

        let first = Task { await store.artwork(for: .song(id: "song-1")) }
        let second = Task { await store.artwork(for: .song(id: "song-1")) }
        let received = [await first.value, await second.value]

        #expect(received == [artwork, artwork])
        #expect(library.requestedSubjects == [.song(id: "song-1")])
    }

    @Test("a subject without artwork resolves to nil without affecting others")
    func missingArtworkIsScopedToItsSubject() async throws {
        let artworkA = try makeArtwork(path: "a")
        let library = FakeArtworkLibrary(artwork: [.song(id: "song-a"): artworkA])
        let store = library.makeStore()

        let receivedA = Task { await store.artwork(for: .song(id: "song-a")) }
        let receivedB = Task { await store.artwork(for: .song(id: "song-b")) }

        #expect(await receivedA.value == artworkA)
        #expect(await receivedB.value == nil)
    }

    @Test("found artwork is returned again without another lookup")
    func foundArtworkIsRemembered() async throws {
        let artwork = try makeArtwork(path: "cached")
        let library = FakeArtworkLibrary(artwork: [.playlist(id: "list"): artwork])
        let store = library.makeStore()

        _ = await store.artwork(for: .playlist(id: "list"))
        let again = await store.artwork(for: .playlist(id: "list"))

        #expect(again == artwork)
        #expect(library.batches.count == 1)
    }

    @Test("missing artwork is looked up again next time")
    func missingArtworkIsRetried() async {
        let library = FakeArtworkLibrary(artwork: [:])
        let store = library.makeStore()

        _ = await store.artwork(for: .artist(id: "artist"))
        _ = await store.artwork(for: .artist(id: "artist"))

        #expect(library.batches.count == 2)
    }

    @Test("lookups are batched five at a time")
    func lookupsAreBatched() async {
        let library = FakeArtworkLibrary(artwork: [:])
        let store = library.makeStore()
        let subjects = (1...7).map { ArtworkSubject.song(id: "song-\($0)") }

        // Callers start in order on the main actor, ahead of the store's
        // first batch, so the queue holds all seven when lookups begin.
        let callers = subjects.map { subject in Task { await store.artwork(for: subject) } }
        for caller in callers {
            _ = await caller.value
        }

        #expect(library.batches.map(\.count) == [5, 2])
        #expect(Set(library.requestedSubjects) == Set(subjects))
    }

    @Test("a cancelled caller stops waiting")
    func cancelledCallerStopsWaiting() async {
        let library = FakeArtworkLibrary(artwork: [:], holdsLookups: true)
        let store = library.makeStore()

        let caller = Task { await store.artwork(for: .song(id: "slow")) }
        try? await Task.sleep(for: .milliseconds(20))
        caller.cancel()

        #expect(await caller.value == nil)
        library.releaseLookups()
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

/// Stands in for the Apple Music library: answers each batch from a fixed
/// table and records what it was asked for.
@MainActor
private final class FakeArtworkLibrary {
    deinit {} // Keep nonisolated: Xcode 27 synthesizes an isolated one that can crash on release. See ViewTeardownTests.

    private let artwork: [ArtworkSubject: Artwork]
    private let holdsLookups: Bool
    private var heldLookups: [CheckedContinuation<Void, Never>] = []
    private(set) var batches: [[ArtworkSubject]] = []

    var requestedSubjects: [ArtworkSubject] { batches.flatMap { $0 } }

    init(artwork: [ArtworkSubject: Artwork], holdsLookups: Bool = false) {
        self.artwork = artwork
        self.holdsLookups = holdsLookups
    }

    func makeStore() -> ArtworkStore {
        ArtworkStore(load: { [self] subjects in await lookUp(subjects) }, pauseBetweenBatches: .zero)
    }

    func releaseLookups() {
        let held = heldLookups
        heldLookups = []
        held.forEach { $0.resume() }
    }

    private func lookUp(_ subjects: [ArtworkSubject]) async -> [ArtworkSubject: Artwork] {
        batches.append(subjects)
        if holdsLookups {
            await withCheckedContinuation { heldLookups.append($0) }
        }
        return artwork.filter { subjects.contains($0.key) }
    }
}
