import Foundation

@Observable
@MainActor
final class ShufflePlayer {
    @ObservationIgnored private let playbackTransport: PlaybackTransport
    @ObservationIgnored private let composer = SessionComposer()
    @ObservationIgnored private var observationTask: Task<Void, Never>?

    @ObservationIgnored private var transitionContinuations: [UUID: AsyncStream<PlaybackTransition>.Continuation] = [:]
    @ObservationIgnored private var publishedSessionID: UUID?
    @ObservationIgnored private var hasStartedSong = false

    /// Each access creates an independent subscription, replaying the current
    /// state before future changes. Buffer all edges, including rapid bursts.
    var playbackTransitions: AsyncStream<PlaybackTransition> {
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

    private(set) var draft: SessionDraft
    private(set) var activeSession: ListeningSession?
    private(set) var playbackState: PlaybackState = .empty
    private(set) var operationNotice: String?
    private(set) var isLoadingSession = false
    private(set) var sessionEndCount = 0
    private(set) var recentPlaybackTrace: [PlaybackTraceEntry] = []

    var songCount: Int { draft.songs.count }
    var allSongs: [Song] { draft.songs }
    var capacity: Int { SessionDraft.maxSongs }
    var remainingCapacity: Int { draft.remainingCapacity }
    var draftIsEmpty: Bool { draft.songs.isEmpty }

    var lastShuffledQueue: [Song] { activeSession?.songOrder ?? [] }
    var transportCurrentSongId: String? { playbackTransport.currentSongId }
    var hasPendingSessionChanges: Bool {
        guard let activeSession else { return !draft.songs.isEmpty }
        return activeSession.songIDs.count != draft.songs.count
            || Set(activeSession.songIDs) != Set(draft.songs.map(\.id))
            || activeSession.algorithm != draft.algorithm
    }

    init(
        playbackTransport: PlaybackTransport,
        initialAlgorithm: ShuffleAlgorithm = .noRepeat
    ) {
        self.playbackTransport = playbackTransport
        self.draft = SessionDraft(algorithm: initialAlgorithm)
        startObserving()
        record("player-created")
    }

    deinit {
        observationTask?.cancel()
        for continuation in transitionContinuations.values {
            continuation.finish()
        }
    }

    func clearOperationNotice() {
        operationNotice = nil
    }

    func stageAlgorithm(_ algorithm: ShuffleAlgorithm) {
        draft = draft.using(algorithm)
        record("algorithm-staged", detail: algorithm.rawValue)
    }

    func addSong(_ song: Song) async throws {
        do {
            let updated = try draft.adding(song)
            guard updated != draft else { return }
            draft = updated
            record("song-added", detail: song.id)
        } catch {
            throw mapDraftError(error)
        }
    }

    func seedSongs(_ songs: [Song]) throws {
        do {
            let updated = try draft.adding(songs)
            guard updated != draft else { return }
            draft = updated
            record("songs-seeded", detail: "\(songs.count)")
        } catch {
            throw mapDraftError(error)
        }
    }

    func addSongsWithQueueRebuild(
        _ songs: [Song],
        algorithm: ShuffleAlgorithm? = nil
    ) async throws {
        if let algorithm {
            draft = draft.using(algorithm)
        }
        try seedSongs(songs)
    }

    func removeSong(id: String) async {
        let updated = draft.removing(songID: id)
        guard updated != draft else { return }
        draft = updated
        record("song-removed", detail: id)
    }

    func removeAllSongs() async {
        draft = draft.removingAll()
        activeSession = nil
        updatePlaybackState(.empty)
        operationNotice = nil
        await playbackTransport.clear()
        record("all-songs-cleared")
    }

    func containsSong(id: String) -> Bool {
        draft.songs.contains { $0.id == id }
    }

    /// Compatibility entry point. It creates one paused immutable session.
    func prepareQueue(algorithm: ShuffleAlgorithm? = nil) async throws {
        if let algorithm {
            draft = draft.using(algorithm)
        }
        guard !draft.songs.isEmpty else { return }
        try await installFreshSession(autoplay: false)
    }

    func startFreshShuffle(
        algorithm: ShuffleAlgorithm? = nil,
        seed: UInt64 = UInt64.random(in: UInt64.min ... UInt64.max)
    ) async throws {
        if let algorithm {
            draft = draft.using(algorithm)
        }
        try await installFreshSession(autoplay: true, seed: seed)
    }

    func play(algorithm: ShuffleAlgorithm? = nil) async throws {
        if let algorithm {
            draft = draft.using(algorithm)
        }
        if activeSession == nil {
            try await installFreshSession(autoplay: true)
            return
        }
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

    func skipToNext() async throws {
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

    func restartOrSkipToPrevious() async throws {
        do {
            try await playbackTransport.restartOrSkipToPrevious()
            record("restart-or-previous")
        } catch {
            throw report("Couldn't go back", error: error)
        }
    }

    func togglePlayback(algorithm: ShuffleAlgorithm? = nil) async throws {
        if playbackState.isPlaying {
            await pause()
        } else {
            try await play(algorithm: algorithm)
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

    func hardResetQueueForDebug() async {
        await removeAllSongs()
        recentPlaybackTrace = []
        record("debug-reset")
    }

    private func installFreshSession(
        autoplay: Bool,
        seed: UInt64 = UInt64.random(in: UInt64.min ... UInt64.max)
    ) async throws {
        let session: ListeningSession
        do {
            session = try composer.compose(draft: draft, seed: seed)
        } catch {
            throw report("Couldn't build a shuffle", error: error)
        }
        try await install(
            session,
            currentSongID: session.songIDs[0],
            playbackPosition: 0,
            autoplay: autoplay
        )
        operationNotice = nil
        record("session-started", detail: "seed=\(seed), autoplay=\(autoplay)")
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

    private func updatePlaybackState(_ state: PlaybackState) {
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
            songTransition = songChanged ? .cleared : nil
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
                await self.handlePlaybackEvent(event)
            }
        }
    }

    private func handlePlaybackEvent(_ event: PlaybackEvent) async {
        // A load commits its state only after the atomic transport operation
        // succeeds. Intermediate transport reports must not escape that boundary.
        guard !isLoadingSession else { return }
        switch event {
        case .stateChanged(let state):
            // MusicKit may briefly report empty while changing entries. The
            // transport's explicit sessionEnded event owns completion.
            if activeSession != nil, (state == .empty || state == .stopped) {
                return
            }
            updatePlaybackState(normalized(state))
            record("transport-state", detail: state.label)
        case .sessionEnded:
            guard activeSession != nil else { return }
            activeSession = nil
            updatePlaybackState(.stopped)
            sessionEndCount &+= 1
            record("session-ended")
            guard !draft.songs.isEmpty else { return }
            do {
                try await installFreshSession(autoplay: true)
            } catch {
                // `installFreshSession` records and exposes the failure.
            }
        }
    }

    private func normalized(_ state: PlaybackState) -> PlaybackState {
        guard let observed = state.currentSong,
              let sessionSong = activeSession?.song(id: observed.id) else {
            return state
        }
        switch state {
        case .playing: return .playing(sessionSong)
        case .paused: return .paused(sessionSong)
        case .loading: return .loading(sessionSong)
        default: return state
        }
    }

    private func mapDraftError(_ error: Error) -> ShufflePlayerError {
        if case ShufflePlayerError.capacityReached = error {
            return .capacityReached
        }
        return .playbackFailed(error.localizedDescription)
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
