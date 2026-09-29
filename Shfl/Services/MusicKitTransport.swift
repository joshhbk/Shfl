import Foundation

/// What the MusicKit transport adapter needs from MusicKit's application player.
///
/// `ApplicationMusicPlayer` is a concrete singleton that can't be substituted,
/// so the adapter touches it only through this surface. Tests drive the adapter
/// with a fake that reproduces MusicKit's quirks.
protocol MusicPlayerSurface: AnyObject {
    /// Resolves `songs` in the user's library and installs the resolved ones as
    /// the queue, starting at `currentSongID`. Songs that no longer resolve are
    /// dropped. Returns the installed songs in queue order.
    func installQueue(_ songs: [Song], startingAt currentSongID: String) async throws -> [Song]

    /// Empties the queue.
    func clearQueue()

    /// The live queue's entry identifiers. MusicKit may replace them when
    /// playback starts.
    var entryIDs: [String] { get }

    var currentEntry: PlayerEntry? { get }
    var status: PlayerStatus { get }
    var playbackTime: TimeInterval { get set }

    func prepareToPlay() async throws
    func play() async throws
    func pause()
    func skipToNextEntry() async throws
    func skipToPreviousEntry() async throws

    /// Fires whenever player state or the queue changes. Read the properties
    /// above for the new values.
    var changes: AsyncStream<Void> { get }
}

/// One queue entry as MusicKit reports it.
struct PlayerEntry: Equatable {
    let id: String
    /// The entry's song with MusicKit's identifiers, or nil when the entry
    /// isn't a song.
    let song: Song?
    let duration: TimeInterval
}

enum PlayerStatus: Equatable {
    case playing
    case paused
    case stopped
    case interrupted
    case seeking
    case unknown
}

/// Hides MusicKit-specific queue loading, identifier mapping, playback timing,
/// and event observation behind Shfl's playback interface.
///
/// Events leave normalised:
/// - The current song is always the listening session's own song, even after
///   MusicKit swaps library identifiers for catalog ones.
/// - While a session is loaded, the brief empty and stopped reports MusicKit
///   makes between entries are not published. Completion is published once, as
///   `.sessionEnded`, after the player stays stopped on the final song.
final class MusicKitTransport: PlaybackTransport {
    private let player: MusicPlayerSurface
    private let confirmationDelay: () async -> Void
    private let playbackEventBroadcaster = PlaybackEventBroadcaster()

    private var stateObservationTask: Task<Void, Never>?
    // MusicKit can replace library Song and Entry IDs when it starts playback.
    // Preserve the session's ordered songs for lookup against the live queue.
    private var sessionSongOrder: [Song] = []
    private var loadedFinalSongID: String?
    private var lastObservedSongID: String?
    private var hasObservedPlaying = false
    private var didPublishSessionEnd = false
    private var sessionEndConfirmationTask: Task<Void, Never>?

    /// - Parameter confirmationDelay: How long the player must stay stopped on
    ///   the final song before the session counts as ended.
    init(
        player: MusicPlayerSurface = ApplicationPlayerSurface(),
        confirmationDelay: @escaping () async -> Void = {
            try? await Task.sleep(for: .milliseconds(350))
        }
    ) {
        self.player = player
        self.confirmationDelay = confirmationDelay
    }

    deinit {
        stateObservationTask?.cancel()
        sessionEndConfirmationTask?.cancel()
        playbackEventBroadcaster.finishAll()
    }

    var playbackEvents: AsyncStream<PlaybackEvent> {
        let stream = playbackEventBroadcaster.stream(
            replaying: .stateChanged(mapPlaybackState())
        )
        startObservingPlaybackStateIfNeeded()
        return stream
    }

    var currentPlaybackTime: TimeInterval {
        player.playbackTime
    }

    var currentSongDuration: TimeInterval {
        player.currentEntry?.duration ?? 0
    }

    var currentSongId: String? {
        player.currentEntry.flatMap(song(for:))?.id
    }

    func load(_ request: PlaybackLoadRequest) async throws {
        guard !request.queue.isEmpty else {
            throw PlaybackLoadError.emptyQueue
        }
        guard request.queue.contains(where: { $0.id == request.currentSongID }) else {
            throw PlaybackLoadError.currentSongMissing(request.currentSongID)
        }

        let resolvedSongs = try await player.installQueue(
            request.queue,
            startingAt: request.currentSongID
        )
        sessionSongOrder = resolvedSongs
        loadedFinalSongID = resolvedSongs.last?.id
        lastObservedSongID = request.currentSongID
        hasObservedPlaying = false
        didPublishSessionEnd = false
        cancelSessionEndConfirmation()

        do {
            try? await player.prepareToPlay()
            player.playbackTime = max(0, request.playbackPosition)
            if request.autoplay {
                try await player.play()
                player.playbackTime = max(0, request.playbackPosition)
            } else {
                player.pause()
            }
        } catch {
            await clear()
            throw error
        }
        emitCurrentState()
    }

    func clear() async {
        sessionSongOrder = []
        loadedFinalSongID = nil
        lastObservedSongID = nil
        hasObservedPlaying = false
        didPublishSessionEnd = false
        cancelSessionEndConfirmation()
        player.pause()
        player.clearQueue()
        emitCurrentState()
    }

    func play() async throws {
        try await player.play()
    }

    func pause() async {
        player.pause()
    }

    func skipToNext() async throws {
        try await player.skipToNextEntry()
    }

    func skipToPrevious() async throws {
        try await player.skipToPreviousEntry()
    }

    func restartOrSkipToPrevious() async throws {
        if player.playbackTime <= 3 {
            try await skipToPrevious()
        } else {
            player.playbackTime = 0
        }
    }

    func seek(to time: TimeInterval) {
        player.playbackTime = max(0, time)
    }

    // MARK: - Observation

    private var isSessionLoaded: Bool {
        !sessionSongOrder.isEmpty && !didPublishSessionEnd
    }

    private func startObservingPlaybackStateIfNeeded() {
        guard stateObservationTask == nil else { return }
        let changes = player.changes
        stateObservationTask = Task { @MainActor [weak self] in
            self?.emitCurrentState()
            for await _ in changes {
                guard !Task.isCancelled, let self else { return }
                self.emitCurrentState()
            }
        }
    }

    private func emitCurrentState() {
        let state = mapPlaybackState()
        if let songID = state.currentSongId {
            lastObservedSongID = songID
        }
        if state.isPlaying {
            hasObservedPlaying = true
            cancelSessionEndConfirmation()
        }

        let reachedLoadedEnd = loadedFinalSongID != nil
            && lastObservedSongID == loadedFinalSongID
            && hasObservedPlaying
            && (state == .empty || player.status == .stopped)
        if reachedLoadedEnd && !didPublishSessionEnd {
            scheduleSessionEndConfirmation()
        }

        // Between entries MusicKit briefly reports no entry or a stopped player.
        // Completion is `.sessionEnded`, so these are not the session's state.
        if isSessionLoaded && (state == .empty || state == .stopped) {
            return
        }

        let didPublish = playbackEventBroadcaster.publish(.stateChanged(state))
        #if DEBUG
        if didPublish {
            print("📻 Emitting state: \(state)")
        }
        #endif
    }

    private func scheduleSessionEndConfirmation() {
        guard sessionEndConfirmationTask == nil else { return }
        let expectedFinalSongID = loadedFinalSongID
        let confirmationDelay = confirmationDelay
        sessionEndConfirmationTask = Task { @MainActor [weak self] in
            await confirmationDelay()
            guard !Task.isCancelled, let self else { return }
            self.sessionEndConfirmationTask = nil

            let stillStopped = self.player.status == .stopped
                || self.player.currentEntry == nil
            guard stillStopped,
                  self.loadedFinalSongID == expectedFinalSongID,
                  self.lastObservedSongID == expectedFinalSongID,
                  self.hasObservedPlaying,
                  !self.didPublishSessionEnd else {
                return
            }

            self.didPublishSessionEnd = true
            self.playbackEventBroadcaster.publish(.sessionEnded)
        }
    }

    private func cancelSessionEndConfirmation() {
        sessionEndConfirmationTask?.cancel()
        sessionEndConfirmationTask = nil
    }

    // MARK: - Mapping

    /// The session's own song for an entry. Resolves by position in the live
    /// queue first, because MusicKit can replace entry and song IDs when
    /// playback starts, then by song ID.
    private func song(for entry: PlayerEntry) -> Song? {
        let liveEntryIDs = player.entryIDs
        if liveEntryIDs.count == sessionSongOrder.count,
           let index = liveEntryIDs.firstIndex(of: entry.id) {
            return sessionSongOrder[index]
        }
        if let reported = entry.song,
           let sessionSong = sessionSongOrder.first(where: { $0.id == reported.id }) {
            return sessionSong
        }
        #if DEBUG
        if !sessionSongOrder.isEmpty {
            print("📻 Session song lookup missed: queue=\(liveEntryIDs.count), session=\(sessionSongOrder.count)")
        }
        #endif
        return entry.song
    }

    private func mapPlaybackState() -> PlaybackState {
        guard let currentEntry = player.currentEntry else {
            return .empty
        }
        guard currentEntry.song != nil, let song = song(for: currentEntry) else {
            return .stopped
        }

        switch player.status {
        case .playing, .seeking:
            return .playing(song)
        case .paused, .interrupted:
            return .paused(song)
        case .stopped:
            // MusicKit can report `.stopped` while a queue entry is loaded (for
            // example after queue restore). Surface that as paused-with-song so
            // the UI can show now-playing metadata without auto-playing.
            return .paused(song)
        case .unknown:
            return .stopped
        }
    }
}

final class PlaybackEventBroadcaster {
    private var continuations: [UUID: AsyncStream<PlaybackEvent>.Continuation] = [:]
    private var latestEvent: PlaybackEvent = .stateChanged(.empty)
    private let lock = NSLock()

    var subscriberCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return continuations.count
    }

    func stream(replaying event: PlaybackEvent) -> AsyncStream<PlaybackEvent> {
        AsyncStream { [weak self] continuation in
            guard let self else {
                continuation.finish()
                return
            }

            let id = UUID()
            let replayEvent: PlaybackEvent

            lock.lock()
            if continuations.isEmpty {
                latestEvent = event
            }
            continuations[id] = continuation
            replayEvent = latestEvent
            lock.unlock()

            continuation.yield(replayEvent)
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.removeSubscriber(id: id)
                }
            }
        }
    }

    @discardableResult
    func publish(_ event: PlaybackEvent) -> Bool {
        let subscribers: [AsyncStream<PlaybackEvent>.Continuation]

        lock.lock()
        if event == latestEvent {
            lock.unlock()
            return false
        }
        latestEvent = event
        subscribers = Array(continuations.values)
        lock.unlock()

        for continuation in subscribers {
            continuation.yield(event)
        }
        return true
    }

    func finishAll() {
        let subscribers: [AsyncStream<PlaybackEvent>.Continuation]

        lock.lock()
        subscribers = Array(continuations.values)
        continuations.removeAll()
        lock.unlock()

        for continuation in subscribers {
            continuation.finish()
        }
    }

    private func removeSubscriber(id: UUID) {
        lock.lock()
        continuations.removeValue(forKey: id)
        lock.unlock()
    }
}
