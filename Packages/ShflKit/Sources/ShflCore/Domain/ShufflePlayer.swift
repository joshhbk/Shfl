import Foundation

@Observable
@MainActor
public final class ShufflePlayer {
    @ObservationIgnored private let playbackTransport: PlaybackTransport
    @ObservationIgnored private let sessionDraft: SessionDraftStore
    @ObservationIgnored private let composer = SessionComposer()
    @ObservationIgnored private var observationTask: Task<Void, Never>?

    @ObservationIgnored private var transitionContinuations: [UUID: AsyncStream<PlaybackTransition>.Continuation] = [:]
    @ObservationIgnored private var publishedSessionID: UUID?
    @ObservationIgnored private var hasStartedSong = false

    // PR 4 → package
    /// Each access creates an independent subscription, replaying the current
    /// state before future changes. Buffer all edges, including rapid bursts.
    public var playbackTransitions: AsyncStream<PlaybackTransition> {
        let id = UUID()
        return AsyncStream { continuation in
            transitionContinuations[id] = continuation
            continuation.yield(PlaybackTransition(
                state: playbackState,
                session: activeSession,
                playbackTime: playbackTransport.currentPlaybackTime,
                songTransition: playbackState.currentSong.map {
                    playbackState.isPlaying ? .selectedAndStarted($0) : .selected($0)
                }
            ))
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.transitionContinuations.removeValue(forKey: id)
                }
            }
        }
    }

    public private(set) var activeSession: ListeningSession?
    public private(set) var playbackState: PlaybackState = .empty
    public private(set) var operationNotice: String?
    public private(set) var isLoadingSession = false
    private(set) var sessionEndCount = 0
    public private(set) var recentPlaybackTrace: [PlaybackTraceEntry] = []

    var lastShuffledQueue: [Song] { activeSession?.songOrder ?? [] }
    public var transportCurrentSongId: String? { playbackTransport.currentSongId }
    public var hasPendingSessionChanges: Bool {
        let draft = sessionDraft.draft
        guard let activeSession else { return !draft.songs.isEmpty }
        return activeSession.songIDs.count != draft.songs.count
            || Set(activeSession.songIDs) != Set(draft.songs.map(\.id))
            || activeSession.algorithm != draft.algorithm
    }

    // PR 4 → package (previews get a ShflDeterministic fixture)
    /// - Parameter sessionDraft: The songs and algorithm used when a new
    ///   shuffle starts.
    public init(
        playbackTransport: PlaybackTransport,
        sessionDraft: SessionDraftStore
    ) {
        self.playbackTransport = playbackTransport
        self.sessionDraft = sessionDraft
        startObserving()
        record("player-created")
    }

    deinit {
        observationTask?.cancel()
        for continuation in transitionContinuations.values {
            continuation.finish()
        }
    }

    public func clearOperationNotice() {
        operationNotice = nil
    }

    /// Stops playback and ends the current listening session.
    func clearSession() async {
        activeSession = nil
        updatePlaybackState(.empty)
        operationNotice = nil
        await playbackTransport.clear()
        record("session-cleared")
    }

    func startFreshShuffle(seed: UInt64) async throws {
        let session: ListeningSession
        do {
            session = try composer.compose(draft: sessionDraft.draft, seed: seed)
        } catch {
            throw report("Couldn't build a shuffle", error: error)
        }
        try await install(
            session,
            currentSongID: session.songIDs[0],
            playbackPosition: 0,
            autoplay: true
        )
        operationNotice = nil
        record("session-started", detail: "seed=\(seed)")
    }

    /// Resumes the active listening session. Does nothing without one: the
    /// session host decides when a new session starts.
    func play() async throws {
        guard activeSession != nil else { return }
        do {
            try await playbackTransport.play()
            record("play")
        } catch {
            throw report("Couldn't start playback", error: error)
        }
    }

    func pause() async {
        await playbackTransport.pause()
        record("pause")
    }

    public func skipToNext() async throws {
        do {
            try await playbackTransport.skipToNext()
            record("skip-next")
        } catch {
            throw report("Couldn't skip to the next song", error: error)
        }
    }

    func skipToPrevious() async throws {
        do {
            try await playbackTransport.skipToPrevious()
            record("skip-previous")
        } catch {
            throw report("Couldn't skip to the previous song", error: error)
        }
    }

    public func restartOrSkipToPrevious() async throws {
        do {
            try await playbackTransport.restartOrSkipToPrevious()
            record("restart-or-previous")
        } catch {
            throw report("Couldn't go back", error: error)
        }
    }

    public func seek(to time: TimeInterval) {
        playbackTransport.seek(to: time)
        record("seek", detail: String(format: "%.1f", time))
    }

    func togglePlayback() async throws {
        if playbackState.isPlaying {
            await pause()
        } else {
            try await play()
        }
    }

    /// Reinstates a self-contained listening session without autoplay.
    func restore(
        _ session: ListeningSession,
        currentSongID: String,
        playbackPosition: TimeInterval
    ) async -> Bool {
        guard session.songIDs.contains(currentSongID) else {
            record("session-restore-failed", detail: "current song not in session")
            return false
        }
        do {
            try await install(
                session,
                currentSongID: currentSongID,
                playbackPosition: playbackPosition,
                autoplay: false
            )
            record("session-restored", detail: session.id.uuidString)
            return true
        } catch {
            record("session-restore-failed", detail: error.localizedDescription)
            return false
        }
    }

    public func hardResetQueueForDebug() async {
        await clearSession()
        recentPlaybackTrace = []
        record("debug-reset")
    }

    private func install(
        _ session: ListeningSession,
        currentSongID: String,
        playbackPosition: TimeInterval,
        autoplay: Bool
    ) async throws {
        guard !isLoadingSession else {
            throw ShufflePlayerError.playbackFailed(
                "A listening session is already loading."
            )
        }
        isLoadingSession = true
        defer { isLoadingSession = false }
        do {
            try await playbackTransport.load(
                PlaybackLoadRequest(
                    sessionID: session.id,
                    queue: session.songOrder,
                    currentSongID: currentSongID,
                    playbackPosition: max(0, playbackPosition),
                    autoplay: autoplay
                )
            )
            activeSession = session
            let currentSong = session.song(id: currentSongID)
            if let currentSong {
                updatePlaybackState(autoplay ? .playing(currentSong) : .paused(currentSong))
            }
        } catch {
            await playbackTransport.clear()
            activeSession = nil
            updatePlaybackState(.error(error))
            throw report("Couldn't load the listening session", error: error)
        }
    }

    /// - Parameter endingSession: The session just played past its last song,
    ///   rather than being cleared.
    private func updatePlaybackState(_ state: PlaybackState, endingSession: Bool = false) {
        let sessionChanged = publishedSessionID != activeSession?.id
        guard state != playbackState || sessionChanged else { return }
        let songChanged = state.currentSongId != playbackState.currentSongId || sessionChanged
        if songChanged { hasStartedSong = false }
        let songTransition: SongTransition?
        if let song = state.currentSong {
            if state.isPlaying && !hasStartedSong {
                songTransition = songChanged ? .selectedAndStarted(song) : .started(song)
                hasStartedSong = true
            } else {
                songTransition = songChanged ? .selected(song) : nil
            }
        } else {
            songTransition = songChanged ? (endingSession ? .sessionEnded : .cleared) : nil
        }
        playbackState = state
        publishedSessionID = activeSession?.id
        let transition = PlaybackTransition(
            state: state,
            session: activeSession,
            playbackTime: playbackTransport.currentPlaybackTime,
            songTransition: songTransition
        )
        for continuation in transitionContinuations.values {
            continuation.yield(transition)
        }
    }

    private func startObserving() {
        let events = playbackTransport.playbackEvents
        observationTask = Task { @MainActor [weak self] in
            for await event in events {
                guard !Task.isCancelled, let self else { return }
                self.handlePlaybackEvent(event)
            }
        }
    }

    private func handlePlaybackEvent(_ event: PlaybackEvent) {
        // A load commits its state only after the atomic transport operation
        // succeeds. Intermediate transport reports must not escape that boundary.
        guard !isLoadingSession else { return }
        switch event {
        case .stateChanged(let state):
            // An active session ends only through `.sessionEnded` or `clear()`.
            // A state report can't end it, including one made before the
            // session loaded but delivered after.
            if activeSession != nil, (state == .empty || state == .stopped) {
                return
            }
            updatePlaybackState(state)
            record("transport-state", detail: state.label)
        case .sessionEnded:
            // The session host decides what follows a session end.
            guard activeSession != nil else { return }
            activeSession = nil
            updatePlaybackState(.stopped, endingSession: true)
            sessionEndCount &+= 1
            record("session-ended")
        }
    }

    private func report(_ action: String, error: Error) -> ShufflePlayerError {
        let message = "\(action). \(error.localizedDescription)"
        operationNotice = message
        record("failure", detail: message)
        return .playbackFailed(message)
    }

    private func record(_ event: String, detail: String? = nil) {
        recentPlaybackTrace.insert(
            PlaybackTraceEntry(event: event, detail: detail),
            at: 0
        )
        if recentPlaybackTrace.count > 50 {
            recentPlaybackTrace.removeLast(recentPlaybackTrace.count - 50)
        }
    }
}

private extension PlaybackState {
    var label: String {
        switch self {
        case .empty: "empty"
        case .stopped: "stopped"
        case .loading(let song): "loading:\(song.id)"
        case .playing(let song): "playing:\(song.id)"
        case .paused(let song): "paused:\(song.id)"
        case .error(let error): "error:\(error.localizedDescription)"
        }
    }
}
