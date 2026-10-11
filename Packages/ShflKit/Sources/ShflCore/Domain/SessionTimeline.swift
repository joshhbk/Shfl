import Foundation

/// Where the listener is in the listening session, and how the session draft has moved on since it was shuffled.
public nonisolated struct SessionTimeline: Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        case idle
        case active
        case ended(at: Date)
    }

    public let status: Status
    public let played: [Song]
    public let current: Song?
    public let upcoming: [Song]
    public let shuffledAt: Date?
    /// In the draft but not the session: they play from the next shuffle.
    public let joiningNextShuffle: Set<String>
    /// In the session but no longer in the draft: they still play this session.
    public let leftPool: Set<String>

    /// The whole session in play order.
    public var songs: [Song] { played + (current.map { [$0] } ?? []) + upcoming }

    public var songCount: Int { played.count + (current == nil ? 0 : 1) + upcoming.count }

    /// One-based; nil when no song is current.
    public var position: Int? { current.map { _ in played.count + 1 } }

    static let idle = SessionTimeline(
        status: .idle,
        played: [],
        current: nil,
        upcoming: [],
        shuffledAt: nil,
        joiningNextShuffle: [],
        leftPool: []
    )

    init(
        activeSession: ListeningSession?,
        currentSongID: String?,
        endedSession: (session: ListeningSession, endedAt: Date)?,
        draftSongIDs: Set<String>
    ) {
        if let session = activeSession {
            let order = session.songOrder
            if let index = currentSongID.flatMap(session.songIDs.firstIndex(of:)) {
                self.init(session: session, status: .active, played: Array(order[..<index]), current: order[index],
                          upcoming: Array(order[(index + 1)...]), draftSongIDs: draftSongIDs)
            } else {
                self.init(session: session, status: .active, played: [], current: nil,
                          upcoming: order, draftSongIDs: draftSongIDs)
            }
        } else if let ended = endedSession {
            self.init(session: ended.session, status: .ended(at: ended.endedAt), played: ended.session.songOrder,
                      current: nil, upcoming: [], draftSongIDs: draftSongIDs)
        } else {
            self = .idle
        }
    }

    private init(
        session: ListeningSession,
        status: Status,
        played: [Song],
        current: Song?,
        upcoming: [Song],
        draftSongIDs: Set<String>
    ) {
        let sessionSongIDs = Set(session.songIDs)
        self.init(
            status: status,
            played: played,
            current: current,
            upcoming: upcoming,
            shuffledAt: session.shuffledAt,
            joiningNextShuffle: draftSongIDs.subtracting(sessionSongIDs),
            leftPool: sessionSongIDs.subtracting(draftSongIDs)
        )
    }

    private init(
        status: Status,
        played: [Song],
        current: Song?,
        upcoming: [Song],
        shuffledAt: Date?,
        joiningNextShuffle: Set<String>,
        leftPool: Set<String>
    ) {
        self.status = status
        self.played = played
        self.current = current
        self.upcoming = upcoming
        self.shuffledAt = shuffledAt
        self.joiningNextShuffle = joiningNextShuffle
        self.leftPool = leftPool
    }
}
