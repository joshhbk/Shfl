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

    private var latestSessionSaveTime: Date?
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
        do {
            // A draft write neither changes the durable session nor supersedes
            // a song-start transition that is still buffered in the stream.
            let session = try archive.load().session
            try archive.commit(pool: player.allSongs, session: session)
        } catch {
            print("💾 Failed to save session draft: \(error)")
        }
    }

    /// A lifecycle checkpoint captures the live position on the active session.
    func checkpoint(position: TimeInterval) {
        let date = now()
        #if DEBUG
        print("💾 Checkpoint: active=\(player.activeSession != nil), current=\(player.playbackState.currentSongId ?? "nil"), position=\(position)")
        #endif
        let record: ListeningSessionRecord?
        if let session = player.activeSession {
            guard let currentSongID = player.playbackState.currentSongId,
                  let checkpoint = ListeningSessionRecord.make(
                    session: session,
                    currentSongID: currentSongID,
                    playbackPosition: position,
                    savedAt: date
                  ) else {
                // An incomplete transport report is not an explicit session clear.
                // Keep the last valid record until a coherent snapshot is available.
                print("💾 Skipped checkpoint: current song does not match the active session")
                return
            }
            record = checkpoint
        } else {
            record = nil
        }
        // Nil is an explicit cleared session, not a reason to retain an older one.
        commit(session: record, savedAt: date)
    }

    private func record(_ transition: PlaybackTransition) {
        switch transition.songTransition {
        case .started, .selectedAndStarted:
            break
        case .cleared:
            commit(session: nil, savedAt: transition.observedAt)
            return
        case .selected, nil:
            return
        }

        guard let record = ListeningSessionRecord.make(
            from: transition,
            savedAt: transition.observedAt
        ) else {
            #if DEBUG
            print("💾 Cannot record song start: active=\(transition.session != nil), current=\(transition.state.currentSongId ?? "nil"), inSession=\(transition.session?.songIDs.contains(transition.state.currentSongId ?? "") == true)")
            #endif
            return
        }

        commit(session: record, savedAt: record.savedAt)
    }

    private func commit(session: ListeningSessionRecord?, savedAt: Date) {
        // A buffered transition must not roll back a newer lifecycle save.
        if let latestSessionSaveTime, savedAt < latestSessionSaveTime { return }

        do {
            try archive.commit(pool: player.allSongs, session: session)
            latestSessionSaveTime = savedAt
            #if DEBUG
            print("💾 Saved: pool=\(player.allSongs.count), current=\(session?.currentSongID ?? "nil"), position=\(session?.playbackPosition ?? 0)")
            #endif
        } catch {
            print("💾 Failed to commit session: \(error)")
        }
    }
}
