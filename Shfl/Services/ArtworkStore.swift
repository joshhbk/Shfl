import Foundation
import MusicKit
import ShflCore

/// Batches library lookups so artwork-heavy lists don't overwhelm MusicKit.
@MainActor
final class ArtworkStore {
    deinit {} // Keep nonisolated: Xcode 27 synthesizes an isolated one that can crash on release. See ViewTeardownTests.

    typealias Loader = @MainActor ([ArtworkSubject]) async -> [ArtworkSubject: Artwork]

    static let batchSize = 5

    private let load: Loader
    private let pauseBetweenBatches: Duration

    private var cache: [ArtworkSubject: Artwork] = [:]
    private var pending: Set<ArtworkSubject> = []
    private var loadQueue: [ArtworkSubject] = []
    private var isProcessing = false
    private var waiters: [ArtworkSubject: [UUID: AsyncStream<Artwork?>.Continuation]] = [:]

    init(
        load: @escaping Loader = ArtworkStore.loadFromLibrary,
        pauseBetweenBatches: Duration = .milliseconds(100)
    ) {
        self.load = load
        self.pauseBetweenBatches = pauseBetweenBatches
    }

    func artwork(for subject: ArtworkSubject) async -> Artwork? {
        if let cached = cache[subject] {
            return cached
        }

        let result = waitForArtwork(for: subject)
        enqueue(subject)
        for await artwork in result {
            return artwork
        }
        return nil
    }

    private func enqueue(_ subject: ArtworkSubject) {
        guard cache[subject] == nil, !pending.contains(subject) else { return }

        pending.insert(subject)
        loadQueue.append(subject)
        processQueue()
    }

    private func processQueue() {
        guard !isProcessing, !loadQueue.isEmpty else { return }

        isProcessing = true

        Task {
            while !loadQueue.isEmpty {
                let batch = Array(loadQueue.prefix(Self.batchSize))
                loadQueue.removeFirst(batch.count)

                let loaded = await load(batch)
                for subject in batch {
                    let artwork = loaded[subject]
                    if let artwork {
                        cache[subject] = artwork
                    }
                    pending.remove(subject)
                    resolveWaiters(for: subject, with: artwork)
                }

                try? await Task.sleep(for: pauseBetweenBatches)
            }
            isProcessing = false
        }
    }

    private func waitForArtwork(for subject: ArtworkSubject) -> AsyncStream<Artwork?> {
        let token = UUID()
        return AsyncStream { continuation in
            waiters[subject, default: [:]][token] = continuation

            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.removeWaiter(for: subject, token: token)
                }
            }
        }
    }

    private func resolveWaiters(for subject: ArtworkSubject, with artwork: Artwork?) {
        guard let subjectWaiters = waiters.removeValue(forKey: subject) else { return }
        for continuation in subjectWaiters.values {
            continuation.yield(artwork)
            continuation.finish()
        }
    }

    private func removeWaiter(for subject: ArtworkSubject, token: UUID) {
        guard var subjectWaiters = waiters[subject] else { return }
        subjectWaiters.removeValue(forKey: token)
        if subjectWaiters.isEmpty {
            waiters.removeValue(forKey: subject)
        } else {
            waiters[subject] = subjectWaiters
        }
    }

    static func loadFromLibrary(_ subjects: [ArtworkSubject]) async -> [ArtworkSubject: Artwork] {
        var songIDs: [MusicItemID] = []
        var artistIDs: [MusicItemID] = []
        var playlistIDs: [MusicItemID] = []
        for subject in subjects {
            switch subject {
            case .song(let id): songIDs.append(MusicItemID(id))
            case .artist(let id): artistIDs.append(MusicItemID(id))
            case .playlist(let id): playlistIDs.append(MusicItemID(id))
            }
        }

        var loaded: [ArtworkSubject: Artwork] = [:]

        if !songIDs.isEmpty {
            var request = MusicLibraryRequest<MusicKit.Song>()
            request.filter(matching: \.id, memberOf: songIDs)
            for song in (try? await request.response().items) ?? [] {
                loaded[.song(id: song.id.rawValue)] = song.artwork
            }
        }

        if !artistIDs.isEmpty {
            var request = MusicLibraryRequest<MusicKit.Artist>()
            request.filter(matching: \.id, memberOf: artistIDs)
            for artist in (try? await request.response().items) ?? [] {
                loaded[.artist(id: artist.id.rawValue)] = artist.artwork
            }
        }

        if !playlistIDs.isEmpty {
            var request = MusicLibraryRequest<MusicKit.Playlist>()
            request.filter(matching: \.id, memberOf: playlistIDs)
            for playlist in (try? await request.response().items) ?? [] {
                loaded[.playlist(id: playlist.id.rawValue)] = playlist.artwork
            }
        }

        return loaded
    }
}
