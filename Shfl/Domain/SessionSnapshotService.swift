import Foundation

@MainActor
final class SessionSnapshotService {
    private let songRepository: SongRepository
    private let playbackStateRepository: PlaybackStateRepository

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
        let playbackSnapshot: PlaybackSessionSnapshot? = {
            guard player.hasRestorableState else { return nil }
            let currentState = player.playbackState
            return PlaybackSessionSnapshot(
                currentSongId: currentState.currentSongId,
                playbackPosition: playbackTime,
                savedAt: Date(),
                queueOrder: player.currentQueueOrder,
                playedSongIds: player.currentPlayedSongIds
            )
        }()

        let snapshot = AppSessionSnapshot(
            songs: player.allSongs,
            playback: playbackSnapshot
        )

        if !player.hasRestorableState {
            print("💾 No restorable playback state to save; persisting songs and clearing playback snapshot")
        }

        #if DEBUG
        let currentSongId = playbackSnapshot?.currentSongId
        let currentSongTitle = player.playbackState.currentSong?.title ?? "nil"
        let queueOrder = playbackSnapshot?.queueOrder ?? []
        let playedIds = playbackSnapshot?.playedSongIds ?? []
        print("💾 Persisting state:")
        print("💾   currentSongId: \(currentSongId ?? "nil")")
        print("💾   currentSongTitle: \(currentSongTitle)")
        print("💾   playbackTime: \(playbackTime)")
        print("💾   queueOrder: \(queueOrder.count) songs, first=\(queueOrder.first ?? "nil")")
        print("💾   playedIds: \(playedIds.count)")
        #endif

        try save(snapshot)

        #if DEBUG
        if let playbackSnapshot {
            print("💾 Saved playback state: song=\(playbackSnapshot.currentSongId ?? "nil"), position=\(playbackSnapshot.playbackPosition), queueOrder=\(queueOrder.count)")
        } else {
            print("💾 Cleared playback state while saving song snapshot")
        }
        #endif
    }

    /// Attempts to restore a saved playback session. Returns true if restoration succeeded.
    /// Owns stale detection, empty-queue guard, and the restore fallback decision.
    func restorePlaybackState(
        _ state: PlaybackSessionSnapshot,
        playbackCoordinator: PlaybackCoordinator
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

        let success = await playbackCoordinator.restoreSession(
            queueOrder: queueOrder,
            currentSongId: state.currentSongId,
            playedIds: playedIds,
            playbackPosition: state.playbackPosition
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
