import Foundation
import MusicKit

/// Hands out MusicKit artwork for library items.
///
/// Callers ask for one subject at a time; the store queues the lookups, asks
/// the library for them in small batches so artwork-heavy lists don't
/// overwhelm MusicKit, shares one lookup between everyone waiting on the same
/// subject, and remembers what it found for the rest of the launch.
/// Each caller awaits only its own subject, so a list of rows never fans out
/// through global observation.
@MainActor
final class ArtworkStore {
    deinit {} // Keep nonisolated: Xcode 27 synthesizes an isolated one that can crash on release. See ViewTeardownTests.

    /// Looks up artwork for one batch of subjects. Subjects missing from the
    /// result have no artwork (or could not be looked up).
    typealias Loader = @MainActor ([ArtworkSubject]) async -> [ArtworkSubject: Artwork]

    static let batchSize = 5

    private let load: Loader
    private let pauseBetweenBatches: Duration

    private var cache: [ArtworkSubject: Artwork] = [:]
    private var pending: Set<ArtworkSubject> = []
    private var loadQueue: [ArtworkSubject] = []
    private var isProcessing = false
    private var waiters: [ArtworkSubject: [UUID: AsyncStream<Artwork?>.Continuation]] = [:]

    /// - Parameters:
    ///   - load: Looks up a batch. Defaults to the user's Apple Music library.
    ///   - pauseBetweenBatches: Breathing room for MusicKit between batches.
    init(
        load: @escaping Loader = ArtworkStore.loadFromLibrary,
        pauseBetweenBatches: Duration = .milliseconds(100)
    ) {
        self.load = load
        self.pauseBetweenBatches = pauseBetweenBatches
    }

    /// The subject's artwork, looking it up if this launch hasn't yet.
    /// Returns nil when the subject has no artwork, the lookup fails, or the
    /// calling task is cancelled while waiting.
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

    // MARK: - Queue

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

    // MARK: - Waiters

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

    // MARK: - Apple Music library

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
