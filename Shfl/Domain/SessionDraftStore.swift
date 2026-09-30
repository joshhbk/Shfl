import Foundation

/// The single place the session draft is edited: which songs are in the pool,
/// the shuffle algorithm, and filling the pool from the library.
///
/// Edits here only shape the next listening session. `ShufflePlayer` reads the
/// draft when it composes a fresh shuffle, and `ListeningSessionHost` saves the
/// pool whenever `songPoolChanges` fires.
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

    /// Each access creates an independent subscription that fires when song-pool
    /// membership changes. Algorithm changes do not fire it. The current pool is
    /// not replayed: subscribers hear only edits made after they subscribe.
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

    /// Adds songs not already in the pool. Throws `.capacityReached` without
    /// changing the pool if they don't all fit.
    func add(_ songs: [Song]) throws {
        draft = try draft.adding(songs)
    }

    func add(_ song: Song) throws {
        try add([song])
    }

    func remove(songID: String) {
        draft = draft.removing(songID: songID)
    }

    /// Empties the pool. A session that is already playing keeps playing.
    func removeAll() {
        draft = draft.removingAll()
    }

    func stage(_ algorithm: ShuffleAlgorithm) {
        draft = draft.using(algorithm)
    }

    /// Fills the remaining capacity with songs from `source` that aren't already
    /// in the pool. Returns how many songs were added.
    @discardableResult
    func autofill(from source: AutofillSource) async throws -> Int {
        let limit = remainingCapacity
        guard limit > 0 else { return 0 }
        let fetched = try await source.fetchSongs(
            excluding: Set(draft.songs.map(\.id)),
            limit: limit
        )
        // The pool may have changed while fetching; add only what still fits.
        let before = songCount
        try add(Array(fetched.filter { !contains($0.id) }.prefix(remainingCapacity)))
        return songCount - before
    }
}
