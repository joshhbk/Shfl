import Foundation

/// Owns one launch's listening session and saves it whenever it changes.
@Observable
@MainActor
public final class ListeningSessionHost {
    @ObservationIgnored public let sessionDraft: SessionDraftStore
    @ObservationIgnored public let player: ShufflePlayer

    /// True from the moment a listening session is asked for until it has
    /// loaded, including any autofill beforehand.
    public var isStartingSession: Bool { isPreparingSession || player.isLoadingSession }

    private var isPreparingSession = false

    @ObservationIgnored private let playbackTransport: PlaybackTransport
    @ObservationIgnored private let archive: SessionArchive
    @ObservationIgnored private let autofillSource: WarmableAutofillSource
    @ObservationIgnored private let makeSeed: () -> UInt64
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let saveAlgorithm: (ShuffleAlgorithm) -> Void
    @ObservationIgnored private let lifecyclePersistenceHook: (() -> Void)?

    /// The session record the archive currently holds, so a pool-only commit
    /// can carry it forward without reading storage back.
    @ObservationIgnored private var committedSession: ListeningSessionRecord?
    @ObservationIgnored private var latestSessionSaveTime: Date?

    @ObservationIgnored private var transitionTask: Task<Void, Never>?
    @ObservationIgnored private var songPoolTask: Task<Void, Never>?
    @ObservationIgnored private var algorithmTask: Task<Void, Never>?

    /// - Parameters:
    ///   - autofillSource: Where autofill finds songs. It is warmed whenever
    ///     the draft is empty, ready for the next press of play.
    ///   - initialAlgorithm: The algorithm the session draft starts with,
    ///     usually the one last saved.
    ///   - saveAlgorithm: Keeps each algorithm staged on the draft for the
    ///     next launch.
    ///   - makeSeed: The seed for each fresh shuffle.
    package init(
        playbackTransport: PlaybackTransport,
        archive: SessionArchive,
        autofillSource: WarmableAutofillSource,
        initialAlgorithm: ShuffleAlgorithm = SessionDraftStore.defaultAlgorithm,
        saveAlgorithm: @escaping (ShuffleAlgorithm) -> Void = { _ in },
        makeSeed: @escaping () -> UInt64 = { UInt64.random(in: UInt64.min ... UInt64.max) },
        now: @escaping () -> Date = Date.init,
        lifecyclePersistenceHook: (() -> Void)? = nil
    ) {
        let sessionDraft = SessionDraftStore(algorithm: initialAlgorithm)
        self.sessionDraft = sessionDraft
        self.player = ShufflePlayer(
            playbackTransport: playbackTransport,
            sessionDraft: sessionDraft
        )
        self.playbackTransport = playbackTransport
        self.archive = archive
        self.autofillSource = autofillSource
        self.makeSeed = makeSeed
        self.now = now
        self.saveAlgorithm = saveAlgorithm
        self.lifecyclePersistenceHook = lifecyclePersistenceHook

        startRecording()
    }

    deinit {
        transitionTask?.cancel()
        songPoolTask?.cancel()
        algorithmTask?.cancel()
    }

    // MARK: - Starting

    /// Plays or pauses the active listening session, whatever the session
    /// draft holds. With no active session, starts a fresh shuffle, autofilling
    /// the draft first when it is empty.
    public func togglePlayback() async {
        guard player.activeSession == nil else {
            try? await player.togglePlayback()
            return
        }
        await startSession(autofillingEmptyDraft: true)
    }

    /// Replaces any active listening session with a fresh shuffle of the draft.
    /// - Parameter autofillingEmptyDraft: Fill an empty draft first, for an
    ///   explicit request to shuffle after the draft was cleared.
    public func startFreshShuffle(autofillingEmptyDraft: Bool = false) async {
        await startSession(autofillingEmptyDraft: autofillingEmptyDraft)
    }

    private func startSession(autofillingEmptyDraft: Bool) async {
        guard !isStartingSession else { return }
        isPreparingSession = true
        defer { isPreparingSession = false }
        do {
            if autofillingEmptyDraft, sessionDraft.isEmpty {
                try await sessionDraft.autofill(from: autofillSource)
            }
            try await player.startFreshShuffle(seed: makeSeed())
        } catch {
            // The player exposes load failures as its operation notice.
            print("Failed to start a listening session: \(error)")
        }
    }

    /// A session that played to its end continues as a fresh shuffle of the
    /// draft. With an empty draft, playback stays stopped: emptying the draft
    /// asked for no more, so there is nothing to autofill.
    private func continueAfterSessionEnd() async {
        guard !sessionDraft.isEmpty else { return }
        await startFreshShuffle()
    }

    // MARK: - Restoring

    /// Reinstates the saved song pool and, when still valid, the saved session.
    /// Returns whether a saved session was loaded into the player.
    @discardableResult
    public func restoreSavedSession() async -> Bool {
        let archived = (try? await archive.loadAsync()) ?? .empty
        committedSession = archived.session

        print("📱 Restore: Loaded \(archived.pool.count) songs, session=\(archived.session != nil ? "exists" : "nil")")

        if archived.pool.isEmpty {
            autofillSource.warm()
        } else {
            try? sessionDraft.add(archived.pool)
        }

        guard let record = archived.session else {
            print("📱 Restore: No saved listening session")
            return false
        }

        print("📱 Restore: Attempting to restore session (song=\(record.currentSongID), position=\(record.playbackPosition))")
        switch record.restored(now: now()) {
        case .restore(let session, let currentSongID, _, let position):
            // Played history is the session order before the current song, so
            // the session and current song fully reinstate it.
            let restored = await player.restore(
                session,
                currentSongID: currentSongID,
                playbackPosition: position
            )
            if !restored {
                print("📱 Restore: Saved session could not be loaded; next play will create a fresh shuffle")
            }
            return restored

        case .discard(let reason):
            print("📱 Restore: Discarding saved session (\(reason))")
            if reason == .stale {
                commit(session: nil, savedAt: now())
            }
            return false
        }
    }

    public func sceneDidLeaveForeground() {
        print("📱 Scene left the foreground - checkpointing session...")
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
                if transition.songTransition == .sessionEnded {
                    await self.continueAfterSessionEnd()
                }
            }
        }

        let songPoolChanges = sessionDraft.songPoolChanges
        songPoolTask = Task { @MainActor [weak self] in
            for await _ in songPoolChanges {
                guard !Task.isCancelled, let self else { return }
                self.commitPool()
                if self.sessionDraft.isEmpty {
                    self.autofillSource.warm()
                }
            }
        }

        let algorithmChanges = sessionDraft.algorithmChanges
        algorithmTask = Task { @MainActor [weak self] in
            for await algorithm in algorithmChanges {
                guard !Task.isCancelled, let self else { return }
                self.saveAlgorithm(algorithm)
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
        case .cleared, .sessionEnded:
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
            try archive.commit(pool: sessionDraft.songs, session: committedSession)
            #if DEBUG
            print("💾 Saved pool: \(sessionDraft.songs.count) songs")
            #endif
        } catch {
            print("💾 Failed to save session draft: \(error)")
        }
    }

    private func commit(session: ListeningSessionRecord?, savedAt: Date) {
        // A buffered transition must not roll back a newer lifecycle save.
        if let latestSessionSaveTime, savedAt < latestSessionSaveTime { return }

        do {
            try archive.commit(pool: sessionDraft.songs, session: session)
            committedSession = session
            latestSessionSaveTime = savedAt
            #if DEBUG
            print("💾 Saved: pool=\(sessionDraft.songs.count), current=\(session?.currentSongID ?? "nil"), position=\(session?.playbackPosition ?? 0)")
            #endif
        } catch {
            print("💾 Failed to commit session: \(error)")
        }
    }
}
