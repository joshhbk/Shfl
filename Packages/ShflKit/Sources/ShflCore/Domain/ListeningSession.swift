import Foundation

@usableFromInline
nonisolated struct SessionDraft: Equatable, Sendable {
    @usableFromInline static let maxSongs = 120
    @usableFromInline static let defaultAlgorithm: ShuffleAlgorithm = .noRepeat
    /// Song counts worth celebrating as the draft fills up.
    static let milestones: Set<Int> = [1, 50, 100, 120]

    private(set) var songs: [Song]
    private(set) var algorithm: ShuffleAlgorithm

    init(
        songs: [Song] = [],
        algorithm: ShuffleAlgorithm = SessionDraft.defaultAlgorithm
    ) {
        let uniqueSongs = Self.unique(songs)
        precondition(
            uniqueSongs.count <= Self.maxSongs,
            "A session draft cannot exceed \(Self.maxSongs) songs."
        )
        self.songs = uniqueSongs
        self.algorithm = algorithm
    }

    var remainingCapacity: Int {
        Self.maxSongs - songs.count
    }

    func adding(_ song: Song) throws -> SessionDraft {
        try adding([song])
    }

    func adding(_ newSongs: [Song]) throws -> SessionDraft {
        let existingIDs = Set(songs.map(\.id))
        let additions = Self.unique(newSongs).filter { !existingIDs.contains($0.id) }
        guard songs.count + additions.count <= Self.maxSongs else {
            throw ShufflePlayerError.capacityReached
        }
        return SessionDraft(songs: songs + additions, algorithm: algorithm)
    }

    func removing(songID: String) -> SessionDraft {
        SessionDraft(
            songs: songs.filter { $0.id != songID },
            algorithm: algorithm
        )
    }

    func removingAll() -> SessionDraft {
        SessionDraft(algorithm: algorithm)
    }

    func replacingSongs(with songs: [Song]) throws -> SessionDraft {
        let uniqueSongs = Self.unique(songs)
        guard uniqueSongs.count <= Self.maxSongs else {
            throw ShufflePlayerError.capacityReached
        }
        return SessionDraft(songs: uniqueSongs, algorithm: algorithm)
    }

    func using(_ algorithm: ShuffleAlgorithm) -> SessionDraft {
        SessionDraft(songs: songs, algorithm: algorithm)
    }

    private static func unique(_ songs: [Song]) -> [Song] {
        var seen = Set<String>()
        return songs.filter { seen.insert($0.id).inserted }
    }
}

public nonisolated struct ListeningSession: Equatable, Sendable {
    public let id: UUID
    public let songOrder: [Song]
    public let algorithm: ShuffleAlgorithm
    public let seed: UInt64
    let createdAt: Date

    init(
        id: UUID = UUID(),
        songOrder: [Song],
        algorithm: ShuffleAlgorithm,
        seed: UInt64,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.songOrder = songOrder
        self.algorithm = algorithm
        self.seed = seed
        self.createdAt = createdAt
    }

    public var songIDs: [String] {
        songOrder.map(\.id)
    }

    func song(id: String) -> Song? {
        songOrder.first { $0.id == id }
    }
}

public nonisolated struct PlaybackTraceEntry: Equatable, Sendable, Identifiable {
    public let id = UUID()
    public let timestamp = Date()
    public let event: String
    public let detail: String?
}

nonisolated enum SessionComposerError: LocalizedError, Equatable {
    case emptyDraft

    var errorDescription: String? {
        switch self {
        case .emptyDraft:
            return "Add at least one song before starting a shuffle."
        }
    }
}

nonisolated struct SessionComposer: Sendable {
    func compose(
        draft: SessionDraft,
        seed: UInt64
    ) throws -> ListeningSession {
        guard !draft.songs.isEmpty else {
            throw SessionComposerError.emptyDraft
        }

        let order = QueueShuffler(
            algorithm: draft.algorithm,
            seed: seed
        ).shuffle(draft.songs)

        return ListeningSession(
            songOrder: order,
            algorithm: draft.algorithm,
            seed: seed
        )
    }
}

nonisolated struct SeededRandomNumberGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }
}
