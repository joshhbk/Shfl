import Foundation

/// The persistence consumer. Subscribes to the player's transition seam and
/// commits a self-contained `ListeningSessionRecord` on durable edges.
///
/// Two inputs: the playback transition stream, and explicit pool-change calls.
/// App lifecycle checkpoints refresh the stored position without replaying a song.
@MainActor
final class SessionRecorder {
    private let archive: SessionArchive
    private let player: ShufflePlayer
    private let now: () -> Date

    private var latestSession: ListeningSessionRecord?
    private var latestCommitTime: Date?
    private var task: Task<Void, Never>?

    init(
        archive: SessionArchive,
        player: ShufflePlayer,
        now: @escaping () -> Date = Date.init
    ) {
        self.archive = archive
        self.player = player
        self.now = now
    }

    deinit {
        task?.cancel()
    }

    func start() {
        let transitions = player.playbackTransitions
        task = Task { @MainActor [weak self] in
            for await transition in transitions {
                guard !Task.isCancelled, let self else { return }
                self.record(transition)
            }
        }
    }

    /// The editable song pool changed; persist it without touching the session.
    func poolDidChange() {
        commit(session: latestSession, savedAt: now())
    }

    /// A lifecycle checkpoint captures the live position on the active session.
    func checkpoint(position: TimeInterval) {
        let date = now()
        let record: ListeningSessionRecord?
        if let latestSession {
            record = latestSession.checkpointed(position: position, at: date)
        } else if let session = player.activeSession,
                  let currentSongID = player.playbackState.currentSongId {
            record = ListeningSessionRecord.make(
                session: session,
                currentSongID: currentSongID,
                playbackPosition: position,
                savedAt: date
            )
        } else {
            record = nil
        }
        guard let record else { return }
        commit(session: record, savedAt: record.savedAt)
    }

    private func record(_ transition: PlaybackTransition) {
        switch transition.songTransition {
        case .started, .selectedAndStarted:
            break
        case .selected, .cleared, nil:
            return
        }

        guard let record = ListeningSessionRecord.make(
            from: transition,
            savedAt: transition.observedAt
        ) else { return }

        commit(session: record, savedAt: record.savedAt)
    }

    private func commit(session: ListeningSessionRecord?, savedAt: Date) {
        // A buffered transition must not roll back a newer lifecycle save.
        if let latestCommitTime, savedAt < latestCommitTime { return }

        do {
            try archive.commit(pool: player.allSongs, session: session)
            latestSession = session
            latestCommitTime = savedAt
        } catch {
            print("💾 Failed to commit session: \(error)")
        }
    }
}