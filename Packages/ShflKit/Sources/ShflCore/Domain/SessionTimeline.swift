import Foundation

/// Where the listener is in the listening session, and how the session draft has moved on since it was shuffled.
public nonisolated struct SessionTimeline: Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        case idle
        case active
        case ended
    }

    private enum Progress: Equatable, Sendable {
        case idle
        /// `current` is nil while the transport reports a song the session doesn't hold.
        case active(played: [Song], current: Song?, upcoming: [Song])
        case ended(played: [Song])
    }

    private let progress: Progress
    /// Empty unless a session is active.
    public let changes: DraftChanges

    public var status: Status {
        switch progress {
        case .idle: .idle
        case .active: .active
        case .ended: .ended
        }
    }

    public var played: [Song] {
        switch progress {
        case .idle: []
        case .active(let played, _, _), .ended(let played): played
        }
    }

    public var current: Song? {
        if case .active(_, let current, _) = progress { current } else { nil }
    }

    public var upcoming: [Song] {
        if case .active(_, _, let upcoming) = progress { upcoming } else { [] }
    }

    /// The whole session in play order.
    public var songs: [Song] { played + (current.map { [$0] } ?? []) + upcoming }

    public var songCount: Int { songs.count }

    /// One-based; nil when no song is current.
    public var position: Int? { current.map { _ in played.count + 1 } }

    static let idle = SessionTimeline(progress: .idle, changes: .none)

    init(phase: SessionPhase, currentSongID: String?, draft: SessionDraft) {
        switch phase {
        case .none:
            self = .idle
        case .active(let session):
            let order = session.songOrder
            let progress: Progress
            if let index = currentSongID.flatMap(session.songIDs.firstIndex(of:)) {
                progress = .active(played: Array(order[..<index]), current: order[index], upcoming: Array(order[(index + 1)...]))
            } else {
                progress = .active(played: [], current: nil, upcoming: order)
            }
            self.init(progress: progress, changes: DraftChanges(session: session, draft: draft))
        case .ended(let session):
            self.init(progress: .ended(played: session.songOrder), changes: .none)
        }
    }

    private init(progress: Progress, changes: DraftChanges) {
        self.progress = progress
        self.changes = changes
    }
}
