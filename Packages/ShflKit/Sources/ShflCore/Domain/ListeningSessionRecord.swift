import Foundation

/// The durable form of a listening session. Self-contained: it carries its own
/// ordered songs, so restoring it never depends on the session draft.
nonisolated struct ListeningSessionRecord: Codable, Equatable, Sendable {
    /// Saved sessions older than this are discarded on launch.
    static let staleAfter: TimeInterval = 7 * 24 * 60 * 60

    let sessionID: UUID
    let songOrder: [Song]
    let algorithm: ShuffleAlgorithm
    let seed: UInt64
    let currentSongID: String
    let playedSongIDs: Set<String>
    let playbackPosition: TimeInterval
    let savedAt: Date

    init(
        sessionID: UUID = UUID(),
        songOrder: [Song],
        algorithm: ShuffleAlgorithm,
        seed: UInt64,
        currentSongID: String,
        playedSongIDs: Set<String>,
        playbackPosition: TimeInterval,
        savedAt: Date
    ) {
        self.sessionID = sessionID
        self.songOrder = songOrder
        self.algorithm = algorithm
        self.seed = seed
        self.currentSongID = currentSongID
        self.playedSongIDs = playedSongIDs
        self.playbackPosition = playbackPosition
        self.savedAt = savedAt
    }

    /// Tolerant restore decision resolved against the record itself. Songs that
    /// no longer resolve in the library are dropped later by the transport.
    func restored(now: Date = Date()) -> RestoreDecision {
        guard !songOrder.isEmpty else { return .discard(.emptyQueue) }
        guard now.timeIntervalSince(savedAt) <= Self.staleAfter else { return .discard(.stale) }
        guard songOrder.contains(where: { $0.id == currentSongID }) else {
            return .discard(.currentSongMissing)
        }
        let session = ListeningSession(
            id: sessionID,
            songOrder: songOrder,
            algorithm: algorithm,
            seed: seed
        )
        return .restore(
            session: session,
            currentSongID: currentSongID,
            playedSongIDs: playedSongIDs,
            playbackPosition: playbackPosition
        )
    }

    /// Builds a record for a live session and position.
    static func make(
        session: ListeningSession,
        currentSongID: String,
        playbackPosition: TimeInterval,
        savedAt: Date
    ) -> ListeningSessionRecord? {
        guard let currentIndex = session.songIDs.firstIndex(of: currentSongID) else {
            return nil
        }
        return ListeningSessionRecord(
            sessionID: session.id,
            songOrder: session.songOrder,
            algorithm: session.algorithm,
            seed: session.seed,
            currentSongID: currentSongID,
            playedSongIDs: Set(session.songIDs.prefix(currentIndex)),
            playbackPosition: playbackPosition,
            savedAt: savedAt
        )
    }

    /// Builds a record for a committed song-start transition. The transition
    /// carries the immutable session, so no live player state is read.
    static func make(from transition: PlaybackTransition, savedAt: Date) -> ListeningSessionRecord? {
        guard let session = transition.session,
              let currentSongID = transition.state.currentSongId else {
            return nil
        }
        return make(
            session: session,
            currentSongID: currentSongID,
            playbackPosition: transition.playbackTime,
            savedAt: savedAt
        )
    }

    /// A copy with a refreshed playback position, used by lifecycle checkpoints.
    func checkpointed(position: TimeInterval, at date: Date) -> ListeningSessionRecord {
        ListeningSessionRecord(
            sessionID: sessionID,
            songOrder: songOrder,
            algorithm: algorithm,
            seed: seed,
            currentSongID: currentSongID,
            playedSongIDs: playedSongIDs,
            playbackPosition: position,
            savedAt: date
        )
    }
}

nonisolated enum RestoreDecision: Equatable, Sendable {
    case restore(
        session: ListeningSession,
        currentSongID: String,
        playedSongIDs: Set<String>,
        playbackPosition: TimeInterval
    )
    case discard(DiscardReason)
}

nonisolated enum DiscardReason: Equatable, Sendable {
    case emptyQueue
    case stale
    case currentSongMissing
}