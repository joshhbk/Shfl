import Foundation

@MainActor
final class SessionSnapshotService {
    private let songRepository: SongRepository
    private let playbackStateRepository: PlaybackStateRepository
    private var latestSaveTime: Date?

    /// Number of days after which saved state is considered stale
    private static let staleThresholdDays: Int = 7

    init(
        songRepository: SongRepository,
        playbackStateRepository: PlaybackStateRepository
    ) {
        self.songRepository = songRepository
        self.playbackStateRepository = playbackStateRepository
    }

    // MARK: - Low-level persistence

    func load() async throws -> AppSessionSnapshot {
        async let songs = songRepository.loadSongsAsync()
        async let playback = playbackStateRepository.loadPlaybackStateAsync()

        return try await AppSessionSnapshot(
            songs: songs,
            playback: playback
        )
    }

    func loadCurrent() throws -> AppSessionSnapshot {
        AppSessionSnapshot(
            songs: try songRepository.loadSongs(),
            playback: try playbackStateRepository.loadPlaybackState()
        )
    }

    func save(_ snapshot: AppSessionSnapshot) throws {
        try songRepository.saveSongs(snapshot.songs)

        if let playback = snapshot.playback {
            try playbackStateRepository.savePlaybackState(playback)
        } else {
            try playbackStateRepository.clearPlaybackState()
        }
    }

    func clearAll() throws {
        try songRepository.clearSongs()
        try playbackStateRepository.clearPlaybackState()
    }

    func clearPlayback() throws {
        try playbackStateRepository.clearPlaybackState()
    }

    // MARK: - Deepened policy interface

    /// Builds and persists a session snapshot from the current player state and playback time.
    /// Owns the decision about what constitutes a restorable snapshot.
    func saveCurrentSession(
        from player: ShufflePlayer,
        playbackTime: TimeInterval
    ) throws {
        try saveSession(
            songs: player.allSongs,
            session: player.activeSession,
            state: player.playbackState,
            playbackTime: playbackTime
        )
    }

    /// Playback edges are detected by ShufflePlayer. Persist the captured
    /// session when a song starts, rather than reading a later player state.
    func savePlaybackTransition(_ transition: PlaybackTransition, songs: [Song]) throws {
        guard transition.startsSong else { return }
        try saveSession(
            songs: songs,
            session: transition.session,
            state: transition.state,
            playbackTime: transition.playbackTime,
            savedAt: transition.observedAt
        )
    }

    private func saveSession(
        songs: [Song],
        session: ListeningSession?,
        state: PlaybackState,
        playbackTime: TimeInterval,
        savedAt: Date = Date()
    ) throws {
        // A background save can run before an already-buffered transition is
        // consumed. Never let that older observation roll persistence back.
        if let latestSaveTime, savedAt < latestSaveTime { return }
        let playback = session.map { session in
            let currentIndex = session.songIDs.firstIndex(of: state.currentSongId ?? "") ?? 0
            return PlaybackSessionSnapshot(
                currentSongId: state.currentSongId,
                playbackPosition: playbackTime,
                savedAt: savedAt,
                queueOrder: session.songIDs,
                playedSongIds: Set(session.songIDs.prefix(currentIndex)),
                algorithm: session.algorithm,
                seed: session.seed
            )
        }
        try save(AppSessionSnapshot(songs: songs, playback: playback))
        latestSaveTime = savedAt
    }

    /// Attempts to restore a saved playback session. Returns true if restoration succeeded.
    /// Owns stale detection, empty-queue guard, and the restore fallback decision.
    func restorePlaybackState(
        _ state: PlaybackSessionSnapshot,
        player: ShufflePlayer
    ) async -> Bool {
        if isPlaybackStateStale(state) {
            print("🔄 Playback state is stale (>7 days), using fresh shuffle")
            try? clearPlayback()
            return false
        }

        let queueOrder = state.queueOrder
        let playedIds = state.playedSongIds

        guard !queueOrder.isEmpty else {
            print("🔄 Saved queue is empty, using fresh shuffle")
            return false
        }

        let success = await player.restoreSession(
            queueOrder: queueOrder,
            currentSongId: state.currentSongId,
            playedIds: playedIds,
            playbackPosition: state.playbackPosition,
            algorithm: state.algorithm,
            seed: state.seed
        )

        if success {
            print("🔄 Restored playback state: song=\(state.currentSongId ?? "nil"), position=\(state.playbackPosition)")
        } else {
            print("🔄 Failed to restore queue, using fresh shuffle")
        }

        return success
    }

    // MARK: - Stale detection

    /// Checks if the given playback state snapshot is older than the stale threshold.
    func isPlaybackStateStale(_ state: PlaybackSessionSnapshot) -> Bool {
        let calendar = Calendar.current
        guard let staleDate = calendar.date(
            byAdding: .day,
            value: -Self.staleThresholdDays,
            to: Date()
        ) else {
            return true
        }
        return state.savedAt < staleDate
    }
}
