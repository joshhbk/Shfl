import Foundation

/// The only place the session draft is edited.
@Observable
@MainActor
public final class SessionDraftStore {
    private(set) var draft: SessionDraft {
        didSet {
            if draft.songs != oldValue.songs {
                for continuation in songPoolContinuations.values {
                    continuation.yield()
                }
            }
            if draft.algorithm != oldValue.algorithm {
                for continuation in algorithmContinuations.values {
                    continuation.yield(draft.algorithm)
                }
            }
        }
    }

    @ObservationIgnored private var songPoolContinuations: [UUID: AsyncStream<Void>.Continuation] = [:]
    @ObservationIgnored private var algorithmContinuations: [UUID: AsyncStream<ShuffleAlgorithm>.Continuation] = [:]

    public nonisolated static let defaultAlgorithm = SessionDraft.defaultAlgorithm

    package init(algorithm: ShuffleAlgorithm = SessionDraftStore.defaultAlgorithm) {
        draft = SessionDraft(algorithm: algorithm)
    }

    deinit {
        for continuation in songPoolContinuations.values {
            continuation.finish()
        }
        for continuation in algorithmContinuations.values {
            continuation.finish()
        }
    }

    /// Each read returns a new stream that fires whenever songs are added to or
    /// removed from the pool, starting with the next edit.
    var songPoolChanges: AsyncStream<Void> {
        let id = UUID()
        return AsyncStream { continuation in
            songPoolContinuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.songPoolContinuations.removeValue(forKey: id)
                }
            }
        }
    }

    /// Yields only changes made after each read.
    var algorithmChanges: AsyncStream<ShuffleAlgorithm> {
        let id = UUID()
        return AsyncStream { continuation in
            algorithmContinuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.algorithmContinuations.removeValue(forKey: id)
                }
            }
        }
    }

    // MARK: - Reading

    public var songs: [Song] { draft.songs }
    public var algorithm: ShuffleAlgorithm { draft.algorithm }
    public var songCount: Int { draft.songs.count }
    public var capacity: Int { SessionDraft.maxSongs }
    public var remainingCapacity: Int { draft.remainingCapacity }
    public var isEmpty: Bool { draft.songs.isEmpty }
    public var isAtCapacity: Bool { draft.remainingCapacity == 0 }

    public func songs(matching query: String) -> [Song] {
        guard !query.isEmpty else { return songs }
        return songs.filter {
            $0.title.localizedStandardContains(query)
                || $0.artist.localizedStandardContains(query)
                || $0.albumTitle.localizedStandardContains(query)
        }
    }

    func contains(_ songID: String) -> Bool {
        draft.songs.contains { $0.id == songID }
    }

    // MARK: - Editing

    /// Adds the songs that aren't already in the pool. If they don't all fit,
    /// throws `.capacityReached` and leaves the pool as it was.
    package func add(_ songs: [Song]) throws {
        draft = try draft.adding(songs)
    }

    func add(_ song: Song) throws {
        try add([song])
    }

    func remove(songID: String) {
        draft = draft.removing(songID: songID)
    }

    /// Empties the pool. Whatever is playing now keeps playing.
    public func removeAll() {
        draft = draft.removingAll()
    }

    public func stage(_ algorithm: ShuffleAlgorithm) {
        draft = draft.using(algorithm)
    }

    /// Adds songs from `source` until the pool is full, skipping ones already
    /// in it. Returns how many songs were added.
    @discardableResult
    func autofill(from source: AutofillSource) async throws -> Int {
        let limit = remainingCapacity
        guard limit > 0 else { return 0 }
        let fetched = try await source.fetchSongs(
            excluding: Set(draft.songs.map(\.id)),
            limit: limit
        )
        // Songs may have been added while this was fetching, so check again.
        let before = songCount
        try add(Array(fetched.filter { !contains($0.id) }.prefix(remainingCapacity)))
        return songCount - before
    }
}
