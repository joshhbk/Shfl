import Foundation

/// Result of a successful session restoration.
struct SessionRestoreResult {
    let restoredQueueState: QueueState
    let restoredPlaybackState: PlaybackState
    let lastObservedSongId: String?
    let pendingRestoreSeek: (songId: String, position: TimeInterval)?
}

/// Encapsulates the multi-step session restoration flow:
/// validate → restore QueueState → replace MusicKit queue → seek → determine playback state.
@MainActor
struct SessionRestorer {
    let musicService: MusicService

    /// Attempts to restore a playback session without auto-starting playback.
    /// - Returns: A `SessionRestoreResult` describing the state changes to apply, or `nil` if restoration failed.
    func restore(
        queueState: QueueState,
        currentPlaybackState: PlaybackState,
        queueOrder: [String],
        currentSongId: String?,
        playedIds: Set<String>,
        playbackPosition: TimeInterval
    ) async -> SessionRestoreResult? {
        print("🔄 restoreSession called: songs=\(queueState.songCount), queueOrder=\(queueOrder.count), currentSongId=\(currentSongId ?? "nil")")

        guard !queueState.isEmpty else {
            print("🔄 restoreSession: No songs in pool, returning nil")
            return nil
        }

        // Attempt to restore from persisted state
        guard let restoredState = queueState.restored(
            queueOrder: queueOrder,
            currentSongId: currentSongId,
            playedIds: playedIds
        ) else {
            print("🔄 restoreSession: Failed to restore state, returning nil")
            return nil
        }

        print("🔄 restoreSession: Restored state with \(restoredState.queueOrder.count) songs, current=\(restoredState.currentSong?.title ?? "none")")

        // Restore queue and position without auto-starting playback.
        do {
            print("🔄 restoreSession: Restoring queue with \(restoredState.queueOrder.count) songs")
            try await musicService.replaceQueue(
                queue: restoredState.queueOrder,
                startAtSongId: restoredState.currentSongId,
                policy: .forcePaused
            )

            // Seek to saved position (best-effort, no autoplay probe).
            let clampedPosition = max(0, playbackPosition)
            var pendingSeek: (songId: String, position: TimeInterval)?
            if clampedPosition > 0 {
                print("🔄 restoreSession: Seeking to position \(clampedPosition)")
                musicService.seek(to: clampedPosition)
                if let currentSongId = restoredState.currentSongId {
                    pendingSeek = (songId: currentSongId, position: clampedPosition)
                }
            }

            print("🔄 restoreSession: Applying paused state without forcing extra transport pause")
            let restoredPlaybackState: PlaybackState
            if let current = restoredState.currentSong {
                // Preserve richer transport metadata (artwork/title updates) when already available.
                let hydratedCurrent: Song
                if let observedCurrent = currentPlaybackState.currentSong, observedCurrent.id == current.id {
                    hydratedCurrent = observedCurrent
                } else {
                    hydratedCurrent = current
                }
                restoredPlaybackState = .paused(hydratedCurrent)
            } else {
                restoredPlaybackState = .stopped
            }

            print("🔄 restoreSession: Success!")
            return SessionRestoreResult(
                restoredQueueState: restoredState,
                restoredPlaybackState: restoredPlaybackState,
                lastObservedSongId: restoredState.currentSongId,
                pendingRestoreSeek: pendingSeek
            )
        } catch {
            print("🔄 restoreSession: Failed to set queue: \(error)")
            return nil
        }
    }
}
