import Foundation

/// Describes the state mutations to apply after resolving a raw MusicKit playback state change.
struct PlaybackStateResolution {
    let resolvedState: PlaybackState
    let resolvedSongId: String?
    let shouldUpdateCurrentSong: Bool
    let songIdToMarkPlayed: String?
    let shouldClearHistory: Bool
    let pendingSeekConsumed: (songId: String, position: TimeInterval)?
}

/// Observes the MusicKit playback state stream and resolves raw states into
/// structured mutations that `ShufflePlayer` applies to its observable state.
///
/// Owns the observation lifecycle and resolution-related private state
/// (`lastObservedSongId`, `suppressHistoryUpdates`, `pendingRestoreSeek`).
@MainActor
final class PlaybackStateObserver {
    /// Last resolved song ID, used to detect song transitions for history tracking.
    private(set) var lastObservedSongId: String?

    /// When true, song transitions do not add the previous song to played history.
    /// Set during multi-step operations like session restoration.
    private(set) var suppressHistoryUpdates = false

    /// Deferred restore seek applied on first explicit user play after restoration.
    private(set) var pendingRestoreSeek: (songId: String, position: TimeInterval)?

    private let musicService: MusicService
    private var stateTask: Task<Void, Never>?

    init(musicService: MusicService) {
        self.musicService = musicService
    }

    func clearLastObservedSongId() {
        lastObservedSongId = nil
    }

    func setLastObservedSongId(_ id: String?) {
        lastObservedSongId = id
    }

    func beginSuppressingHistory() {
        suppressHistoryUpdates = true
    }

    func endSuppressingHistory() {
        suppressHistoryUpdates = false
    }

    func setPendingRestoreSeek(songId: String, position: TimeInterval) {
        pendingRestoreSeek = (songId: songId, position: position)
    }

    func clearPendingRestoreSeek() {
        pendingRestoreSeek = nil
    }

    deinit {
        stateTask?.cancel()
    }

    /// Starts observing the MusicKit playback state stream.
    /// Each raw state is resolved against the current `queueState` (fetched via the closure)
    /// and the resulting `PlaybackStateResolution` is delivered to `onResolution`.
    func startObserving(
        queueState: @escaping @MainActor () -> QueueState,
        onResolution: @escaping @MainActor (PlaybackStateResolution) -> Void
    ) {
        stateTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await rawState in self.musicService.playbackStateStream {
                let resolution = self.resolve(rawState, queueState: queueState())
                onResolution(resolution)
            }
        }
    }

    func stopObserving() {
        stateTask?.cancel()
        stateTask = nil
    }

    /// Resolves a raw MusicKit state against the current queue state.
    /// Returns a description of what mutations to apply.
    /// Note: mutates `lastObservedSongId` and `pendingRestoreSeek` as side effects.
    func resolve(_ newState: PlaybackState, queueState: QueueState) -> PlaybackStateResolution {
        // MusicKit can emit .stopped while a queue/current entry still exists after restore.
        // Preserve the visible "current song loaded but not playing" state in that case.
        let normalizedState: PlaybackState
        if case .stopped = newState,
           let current = queueState.currentSong,
           suppressHistoryUpdates {
            normalizedState = .paused(current)
        } else {
            normalizedState = newState
        }

        // If the queue is empty, ignore any MusicKit states with songs (they're stale)
        if queueState.isEmpty && normalizedState.currentSong != nil {
            lastObservedSongId = nil
            return PlaybackStateResolution(
                resolvedState: .empty,
                resolvedSongId: nil,
                shouldUpdateCurrentSong: false,
                songIdToMarkPlayed: nil,
                shouldClearHistory: false,
                pendingSeekConsumed: nil
            )
        }

        // Resolve IDs in a deterministic order:
        // 1. Exact ID match
        // 2. Metadata fallback (title + artist + album)
        let resolvedState: PlaybackState
        let resolvedSongId: String?

        if let musicKitSong = normalizedState.currentSong,
           let poolSong = queueState.songPool.first(where: { $0.id == musicKitSong.id }) ??
            queueState.songPool.first(where: {
                $0.title == musicKitSong.title &&
                $0.artist == musicKitSong.artist &&
                $0.albumTitle == musicKitSong.albumTitle
            }) {
            // Found a stable mapping in the pool. Keep MusicKit artwork freshness.
            resolvedSongId = poolSong.id
            let mergedSong = Song(
                id: poolSong.id,
                title: musicKitSong.title,
                artist: musicKitSong.artist,
                albumTitle: musicKitSong.albumTitle,
                artworkURL: musicKitSong.artworkURL,
                playCount: musicKitSong.playCount,
                lastPlayedDate: musicKitSong.lastPlayedDate
            )
            switch normalizedState {
            case .playing:
                resolvedState = .playing(mergedSong)
            case .paused:
                resolvedState = .paused(mergedSong)
            case .loading:
                resolvedState = .loading(mergedSong)
            default:
                resolvedState = normalizedState
            }
        } else {
            // No match in pool - use MusicKit's data as-is
            resolvedSongId = normalizedState.currentSongId
            resolvedState = normalizedState
        }

        // Determine history tracking
        let songIdToMarkPlayed: String?
        if !suppressHistoryUpdates,
           let lastId = lastObservedSongId,
           lastId != resolvedSongId {
            songIdToMarkPlayed = lastId
        } else {
            songIdToMarkPlayed = nil
        }
        lastObservedSongId = resolvedSongId

        // Clear history on stop/empty/error
        let shouldClearHistory: Bool
        switch resolvedState {
        case .stopped, .empty, .error:
            shouldClearHistory = true
            lastObservedSongId = nil
        default:
            shouldClearHistory = false
        }

        // Check for pending restore seek
        let pendingSeekConsumed: (songId: String, position: TimeInterval)?
        if case .playing = resolvedState,
           let pendingSeek = pendingRestoreSeek,
           let resolvedSongId,
           pendingSeek.songId == resolvedSongId {
            pendingRestoreSeek = nil
            pendingSeekConsumed = pendingSeek
        } else {
            pendingSeekConsumed = nil
        }

        return PlaybackStateResolution(
            resolvedState: resolvedState,
            resolvedSongId: resolvedSongId,
            shouldUpdateCurrentSong: resolvedSongId != nil,
            songIdToMarkPlayed: songIdToMarkPlayed,
            shouldClearHistory: shouldClearHistory,
            pendingSeekConsumed: pendingSeekConsumed
        )
    }
}
