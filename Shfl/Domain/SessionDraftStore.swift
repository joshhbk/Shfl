import Foundation

/// The one place the session draft is edited: which songs are in the pool,
/// the shuffle algorithm, and filling the pool from the library.
///
/// Edits here apply to the next shuffle. `ShufflePlayer` reads the draft when
/// it starts a new shuffle, and `ListeningSessionHost` saves the pool whenever
/// `songPoolChanges` fires.
@Observable
@MainActor
final class SessionDraftStore {
    private(set) var draft: SessionDraft {
        didSet {
            guard draft.songs != oldValue.songs else { return }
            for continuation in songPoolContinuations.values {
                continuation.yield()
            }
        }
    }

    @ObservationIgnored private var songPoolContinuations: [UUID: AsyncStream<Void>.Continuation] = [:]

    init(algorithm: ShuffleAlgorithm = .noRepeat) {
        draft = SessionDraft(algorithm: algorithm)
    }

    deinit {
        for continuation in songPoolContinuations.values {
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

    // MARK: - Reading

    var songs: [Song] { draft.songs }
    var algorithm: ShuffleAlgorithm { draft.algorithm }
    var songCount: Int { draft.songs.count }
    var capacity: Int { SessionDraft.maxSongs }
    var remainingCapacity: Int { draft.remainingCapacity }
    var isEmpty: Bool { draft.songs.isEmpty }
    var isAtCapacity: Bool { draft.remainingCapacity == 0 }

    func contains(_ songID: String) -> Bool {
        draft.songs.contains { $0.id == songID }
    }

    // MARK: - Editing

    /// Adds the songs that aren't already in the pool. If they don't all fit,
    /// throws `.capacityReached` and leaves the pool as it was.
    func add(_ songs: [Song]) throws {
        draft = try draft.adding(songs)
    }

    func add(_ song: Song) throws {
        try add([song])
    }

    func remove(songID: String) {
        draft = draft.removing(songID: songID)
    }

    /// Empties the pool. Whatever is playing now keeps playing.
    func removeAll() {
        draft = draft.removingAll()
    }

    func stage(_ algorithm: ShuffleAlgorithm) {
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
