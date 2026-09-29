import Foundation
import UIKit

/// Owns one launch's listening session: the player that holds the session
/// draft and the active session, session restore, and durability.
///
/// Durability is driven by state, never by callers. Song-pool edits arrive on
/// the player's draft seam, song starts on its transition seam, and lifecycle
/// checkpoints on the background notification. Each commit writes the live
/// pool together with the latest session record, so the two can never disagree.
@Observable
@MainActor
final class ListeningSessionHost {
    let player: ShufflePlayer

    private(set) var didRestorePlaybackState = false

    @ObservationIgnored private let playbackTransport: PlaybackTransport
    @ObservationIgnored private let archive: SessionArchive
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let lifecyclePersistenceHook: (() -> Void)?

    /// The session record the archive currently holds, so a pool-only commit
    /// can carry it forward without reading storage back.
    @ObservationIgnored private var committedSession: ListeningSessionRecord?
    @ObservationIgnored private var latestSessionSaveTime: Date?

    @ObservationIgnored private var transitionTask: Task<Void, Never>?
    @ObservationIgnored private var draftTask: Task<Void, Never>?
    @ObservationIgnored private var backgroundObserver: NSObjectProtocol?

    init(
        playbackTransport: PlaybackTransport,
        archive: SessionArchive,
        initialAlgorithm: ShuffleAlgorithm = .noRepeat,
        now: @escaping () -> Date = Date.init,
        lifecyclePersistenceHook: (() -> Void)? = nil
    ) {
        self.player = ShufflePlayer(
            playbackTransport: playbackTransport,
            initialAlgorithm: initialAlgorithm
        )
        self.playbackTransport = playbackTransport
        self.archive = archive
        self.now = now
        self.lifecyclePersistenceHook = lifecyclePersistenceHook

        startRecording()
        subscribeToBackgroundNotification()
    }

    deinit {
        transitionTask?.cancel()
        draftTask?.cancel()
        if let observer = backgroundObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Reinstates the saved song pool and, when still valid, the saved session.
    func restoreSavedSession() async {
        let archived = (try? await archive.loadAsync()) ?? .empty
        committedSession = archived.session

        print("📱 Restore: Loaded \(archived.pool.count) songs, session=\(archived.session != nil ? "exists" : "nil")")

        if !archived.pool.isEmpty {
            try? player.seedSongs(archived.pool)
        }

        guard let record = archived.session else {
            print("📱 Restore: No saved listening session")
            return
        }

        print("📱 Restore: Attempting to restore session (song=\(record.currentSongID), position=\(record.playbackPosition))")
        switch record.restored(now: now()) {
        case .restore(let session, let currentSongID, _, let position):
            // Played history is the session order before the current song, so
            // the session and current song fully reinstate it.
            didRestorePlaybackState = await player.restore(
                session,
                currentSongID: currentSongID,
                playbackPosition: position
            )
            if !didRestorePlaybackState {
                print("📱 Restore: Saved session could not be loaded; next play will create a fresh shuffle")
            }

        case .discard(let reason):
            print("📱 Restore: Discarding saved session (\(reason))")
            if reason == .stale {
                commit(session: nil, savedAt: now())
            }
        }
    }

    /// A lifecycle checkpoint captures the live position on the active session.
    func handleDidEnterBackground() {
        print("📱 App entering background - checkpointing session...")
        checkpoint(position: playbackTransport.currentPlaybackTime)
        lifecyclePersistenceHook?()
    }

    // MARK: - Recording

    private func startRecording() {
        let transitions = player.playbackTransitions
        transitionTask = Task { @MainActor [weak self] in
            for await transition in transitions {
                guard !Task.isCancelled, let self else { return }
                self.record(transition)
            }
        }

        let draftChanges = player.draftChanges
        draftTask = Task { @MainActor [weak self] in
            for await _ in draftChanges {
                guard !Task.isCancelled, let self else { return }
                self.commitPool()
            }
        }
    }

    private func checkpoint(position: TimeInterval) {
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

    /// A draft edit neither changes the durable session nor supersedes a
    /// song-start transition still buffered on the transition seam.
    private func commitPool() {
        do {
            try archive.commit(pool: player.allSongs, session: committedSession)
            #if DEBUG
            print("💾 Saved pool: \(player.allSongs.count) songs")
            #endif
        } catch {
            print("💾 Failed to save session draft: \(error)")
        }
    }

    private func commit(session: ListeningSessionRecord?, savedAt: Date) {
        // A buffered transition must not roll back a newer lifecycle save.
        if let latestSessionSaveTime, savedAt < latestSessionSaveTime { return }

        do {
            try archive.commit(pool: player.allSongs, session: session)
            committedSession = session
            latestSessionSaveTime = savedAt
            #if DEBUG
            print("💾 Saved: pool=\(player.allSongs.count), current=\(session?.currentSongID ?? "nil"), position=\(session?.playbackPosition ?? 0)")
            #endif
        } catch {
            print("💾 Failed to commit session: \(error)")
        }
    }

    private func subscribeToBackgroundNotification() {
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleDidEnterBackground()
            }
        }
    }
}
