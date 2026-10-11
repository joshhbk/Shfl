import Foundation

/// How the session draft has moved on since the active listening session was shuffled.
public nonisolated struct DraftChanges: Equatable, Sendable {
    /// In the draft but not the session: they play from the next shuffle.
    public let joiningNextShuffle: Set<String>
    /// In the session but no longer in the draft: they still play this session.
    public let leftPool: Set<String>
    public let algorithmChanged: Bool

    public var isEmpty: Bool { joiningNextShuffle.isEmpty && leftPool.isEmpty && !algorithmChanged }

    static let none = DraftChanges(joiningNextShuffle: [], leftPool: [], algorithmChanged: false)

    init(session: ListeningSession, draft: SessionDraft) {
        let sessionSongIDs = Set(session.songIDs)
        let draftSongIDs = Set(draft.songs.map(\.id))
        self.init(
            joiningNextShuffle: draftSongIDs.subtracting(sessionSongIDs),
            leftPool: sessionSongIDs.subtracting(draftSongIDs),
            algorithmChanged: session.algorithm != draft.algorithm
        )
    }

    private init(joiningNextShuffle: Set<String>, leftPool: Set<String>, algorithmChanged: Bool) {
        self.joiningNextShuffle = joiningNextShuffle
        self.leftPool = leftPool
        self.algorithmChanged = algorithmChanged
    }
}
