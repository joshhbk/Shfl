import Foundation

struct QueueEngineState: Equatable, Sendable {
    var queueState: QueueState
    var playbackState: PlaybackState
    var revision: Int
    var queueNeedsBuild: Bool
}

enum TransportCommand: Sendable {
    case setQueue(songs: [Song], revision: Int)
    case insertIntoQueue(songs: [Song], revision: Int)
    case replaceQueue(queue: [Song], startAtSongId: String?, policy: QueueApplyPolicy, revision: Int)
    case play(revision: Int)
    case pause(revision: Int)
    case skipToNext(revision: Int)
    case skipToPrevious(revision: Int)
    case restartOrSkipToPrevious(revision: Int)

    var revision: Int {
        switch self {
        case .setQueue(_, let revision):
            return revision
        case .insertIntoQueue(_, let revision):
            return revision
        case .replaceQueue(_, _, _, let revision):
            return revision
        case .play(let revision):
            return revision
        case .pause(let revision):
            return revision
        case .skipToNext(let revision):
            return revision
        case .skipToPrevious(let revision):
            return revision
        case .restartOrSkipToPrevious(let revision):
            return revision
        }
    }

    func withRevision(_ revision: Int) -> TransportCommand {
        switch self {
        case .setQueue(let songs, _):
            return .setQueue(songs: songs, revision: revision)
        case .insertIntoQueue(let songs, _):
            return .insertIntoQueue(songs: songs, revision: revision)
        case .replaceQueue(let queue, let startAtSongId, let policy, _):
            return .replaceQueue(queue: queue, startAtSongId: startAtSongId, policy: policy, revision: revision)
        case .play:
            return .play(revision: revision)
        case .pause:
            return .pause(revision: revision)
        case .skipToNext:
            return .skipToNext(revision: revision)
        case .skipToPrevious:
            return .skipToPrevious(revision: revision)
        case .restartOrSkipToPrevious:
            return .restartOrSkipToPrevious(revision: revision)
        }
    }
}

enum QueueIntent: Sendable {
    case addSong(Song)
    case addSongs([Song])
    case addSongsWithRebuild([Song], algorithm: ShuffleAlgorithm?)
    case removeSong(id: String)
    case removeAllSongs
    case prepareQueue(algorithm: ShuffleAlgorithm?)
    case play(algorithm: ShuffleAlgorithm?)
    case pause
    case skipToNext
    case skipToPrevious
    case restartOrSkipToPrevious
    case togglePlayback(algorithm: ShuffleAlgorithm?)
    case reshuffleAlgorithm(ShuffleAlgorithm)
    case playbackResolution(PlaybackStateResolution)
    case restoreSession(queueState: QueueState, playbackState: PlaybackState)
}

enum QueueEngineError: Error {
    case capacityReached
}

struct QueueEngineReduction: Sendable {
    let nextState: QueueEngineState
    let transportCommands: [TransportCommand]
    let wasNoOp: Bool
}

enum QueueEngineReducer {
    static func reduce(
        state: QueueEngineState,
        intent: QueueIntent
    ) throws -> QueueEngineReduction {
        var nextQueueState = state.queueState
        var nextPlaybackState = state.playbackState
        var nextQueueNeedsBuild = state.queueNeedsBuild
        var commands: [TransportCommand] = []

        switch intent {
        case .addSong(let song):
            guard let updatedPoolState = state.queueState.addingSong(song) else {
                throw QueueEngineError.capacityReached
            }

            // Duplicate add is a no-op.
            if updatedPoolState.songCount == state.queueState.songCount {
                return QueueEngineReduction(nextState: state, transportCommands: [], wasNoOp: true)
            }

            nextQueueState = updatedPoolState

            if state.playbackState.isActive && state.queueState.hasQueue {
                let canAppendViaInsert =
                    !state.queueNeedsBuild &&
                    !state.queueState.isQueueStale &&
                    state.playbackState.currentSongId != nil

                if canAppendViaInsert, let currentId = state.playbackState.currentSongId {
                    nextQueueState = nextQueueState.appendingToQueue(song)
                    nextQueueState = nextQueueState.settingCurrentSong(id: currentId)
                    commands.append(.insertIntoQueue(songs: [song], revision: 0))
                    nextQueueNeedsBuild = false
                } else {
                    // Active playback with stale queue shape: rebuild immediately instead of deferring UX.
                    let algorithm = nextQueueState.algorithm
                    let preferredCurrentSongId = state.playbackState.currentSongId ?? state.queueState.currentSongId
                    nextQueueState = nextQueueState.reshuffledUpcoming(
                        with: algorithm,
                        preferredCurrentSongId: preferredCurrentSongId
                    )
                    let policy: QueueApplyPolicy = state.playbackState.isPlaying ? .forcePlaying : .forcePaused
                    commands.append(
                        .replaceQueue(
                            queue: nextQueueState.queueOrder,
                            startAtSongId: nextQueueState.currentSongId,
                            policy: policy,
                            revision: 0
                        )
                    )
                    nextQueueNeedsBuild = false
                }
            } else if state.queueState.hasQueue {
                // Keep the existing queue for now; rebuild on next play.
                nextQueueNeedsBuild = true
            }

        case .addSongs(let songs):
            guard let updatedPoolState = state.queueState.addingSongs(songs) else {
                throw QueueEngineError.capacityReached
            }
            nextQueueState = updatedPoolState
            if state.queueState.hasQueue {
                nextQueueNeedsBuild = true
            }

        case .addSongsWithRebuild(let songs, let algorithm):
            guard let updatedPoolState = state.queueState.addingSongs(songs) else {
                throw QueueEngineError.capacityReached
            }
            nextQueueState = updatedPoolState

            if state.playbackState.isActive,
               let currentSongId = state.playbackState.currentSongId,
               nextQueueState.containsSong(id: currentSongId) {
                let effectiveAlgorithm = algorithm ?? nextQueueState.algorithm
                nextQueueState = nextQueueState.settingCurrentSong(id: currentSongId)
                nextQueueState = nextQueueState.reshuffledUpcoming(
                    with: effectiveAlgorithm,
                    preferredCurrentSongId: currentSongId
                )

                let policy: QueueApplyPolicy = state.playbackState.isPlaying ? .forcePlaying : .forcePaused
                commands.append(
                    .replaceQueue(
                        queue: nextQueueState.queueOrder,
                        startAtSongId: currentSongId,
                        policy: policy,
                        revision: 0
                    )
                )
                nextQueueNeedsBuild = false
            } else if state.playbackState.isActive {
                nextQueueNeedsBuild = true
            } else if state.queueState.hasQueue {
                // Queue is now stale relative to pool while inactive.
                nextQueueNeedsBuild = true
            }

        case .removeSong(let id):
            let isRemovingCurrentSong = state.playbackState.currentSongId == id
            nextQueueState = state.queueState.removingSong(id: id)

            if state.playbackState.isActive {
                if isRemovingCurrentSong {
                    commands.append(.skipToNext(revision: 0))
                } else if let currentSongId = state.playbackState.currentSongId,
                          nextQueueState.containsSong(id: currentSongId) {
                    let policy: QueueApplyPolicy = state.playbackState.isPlaying ? .forcePlaying : .forcePaused
                    commands.append(
                        .replaceQueue(
                            queue: nextQueueState.queueOrder,
                            startAtSongId: currentSongId,
                            policy: policy,
                            revision: 0
                        )
                    )
                } else if nextQueueState.isEmpty {
                    commands.append(.pause(revision: 0))
                    nextPlaybackState = .empty
                }
            }

            if !nextQueueState.hasQueue && !nextQueueState.isEmpty {
                nextQueueNeedsBuild = true
            }

        case .removeAllSongs:
            nextQueueState = .empty
            nextPlaybackState = .empty
            nextQueueNeedsBuild = false
            commands.append(.pause(revision: 0))

        case .prepareQueue(let algorithm):
            guard !state.queueState.isEmpty else {
                return QueueEngineReduction(nextState: state, transportCommands: [], wasNoOp: true)
            }
            let effectiveAlgorithm = algorithm ?? state.queueState.algorithm
            nextQueueState = state.queueState.shuffled(with: effectiveAlgorithm)
            nextQueueNeedsBuild = false
            commands.append(.setQueue(songs: nextQueueState.queueOrder, revision: 0))

        case .play(let algorithm):
            guard !state.queueState.isEmpty else {
                return QueueEngineReduction(nextState: state, transportCommands: [], wasNoOp: true)
            }

            nextQueueState = state.queueState.clearingPlayedHistory()

            if !nextQueueState.hasQueue || state.queueNeedsBuild {
                let effectiveAlgorithm = algorithm ?? nextQueueState.algorithm
                nextQueueState = nextQueueState.shuffled(with: effectiveAlgorithm)
                commands.append(.setQueue(songs: nextQueueState.queueOrder, revision: 0))
                nextQueueNeedsBuild = false
            }

            if let current = nextQueueState.currentSong {
                nextPlaybackState = .loading(current)
            }
            commands.append(.play(revision: 0))

        case .pause:
            commands.append(.pause(revision: 0))

        case .skipToNext:
            commands.append(.skipToNext(revision: 0))

        case .skipToPrevious:
            commands.append(.skipToPrevious(revision: 0))

        case .restartOrSkipToPrevious:
            commands.append(.restartOrSkipToPrevious(revision: 0))

        case .togglePlayback(let algorithm):
            switch state.playbackState {
            case .empty, .stopped:
                return try reduce(state: state, intent: .play(algorithm: algorithm))
            case .playing:
                return try reduce(state: state, intent: .pause)
            case .paused:
                if !state.queueState.isEmpty && (!state.queueState.hasQueue || state.queueNeedsBuild) {
                    return try reduce(state: state, intent: .play(algorithm: algorithm))
                }
                commands.append(.play(revision: 0))
            case .loading:
                return QueueEngineReduction(nextState: state, transportCommands: [], wasNoOp: true)
            case .error:
                return try reduce(state: state, intent: .play(algorithm: algorithm))
            }

        case .reshuffleAlgorithm(let algorithm):
            guard !state.queueState.isEmpty else {
                return QueueEngineReduction(nextState: state, transportCommands: [], wasNoOp: true)
            }

            if !state.playbackState.isActive {
                nextQueueState = state.queueState.invalidatingQueue(using: algorithm)
                nextQueueNeedsBuild = true
                break
            }

            guard let currentSongId = state.playbackState.currentSongId,
                  state.queueState.containsSong(id: currentSongId) else {
                return QueueEngineReduction(nextState: state, transportCommands: [], wasNoOp: true)
            }

            nextQueueState = state.queueState.settingCurrentSong(id: currentSongId)
            nextQueueState = nextQueueState.reshuffledUpcoming(
                with: algorithm,
                preferredCurrentSongId: currentSongId
            )
            nextQueueNeedsBuild = false

            let policy: QueueApplyPolicy = state.playbackState.isPlaying ? .forcePlaying : .forcePaused
            commands.append(
                .replaceQueue(
                    queue: nextQueueState.queueOrder,
                    startAtSongId: currentSongId,
                    policy: policy,
                    revision: 0
                )
            )

        case .playbackResolution(let resolution):
            if resolution.shouldUpdateCurrentSong, let songId = resolution.resolvedSongId {
                nextQueueState = nextQueueState.settingCurrentSong(id: songId)
            }
            if let playedId = resolution.songIdToMarkPlayed {
                nextQueueState = nextQueueState.markingAsPlayed(id: playedId)
            }
            if resolution.shouldClearHistory {
                nextQueueState = nextQueueState.clearingPlayedHistory()
                if !nextQueueState.isEmpty {
                    let isTransientStopDuringStartup: Bool
                    switch (state.playbackState, resolution.resolvedState) {
                    case (.loading, .stopped):
                        // `setQueue` can emit `.stopped` before the queued `.play` command resolves.
                        // Keep the freshly built queue valid for this transient transport state.
                        isTransientStopDuringStartup = true
                    default:
                        isTransientStopDuringStartup = false
                    }

                    if !isTransientStopDuringStartup {
                        // A terminal stop/empty/error transition should replay from a fresh queue build.
                        nextQueueNeedsBuild = true
                    }
                }
            }
            nextPlaybackState = resolution.resolvedState
            if !commands.isEmpty {
#if DEBUG
                assertionFailure("playbackResolution must not emit transport commands")
#endif
                commands.removeAll()
            }

        case .restoreSession(let restoredQueueState, let restoredPlaybackState):
            nextQueueState = restoredQueueState
            nextPlaybackState = restoredPlaybackState
            nextQueueNeedsBuild = false
        }

        let didMutate =
            nextQueueState != state.queueState ||
            nextPlaybackState != state.playbackState ||
            nextQueueNeedsBuild != state.queueNeedsBuild ||
            !commands.isEmpty

        guard didMutate else {
            return QueueEngineReduction(nextState: state, transportCommands: [], wasNoOp: true)
        }

        let revision: Int
        switch intent {
        case .playbackResolution:
            // Playback observer updates should not invalidate in-flight transport batches.
            revision = state.revision
        default:
            revision = state.revision + 1
        }
        let nextState = QueueEngineState(
            queueState: nextQueueState,
            playbackState: nextPlaybackState,
            revision: revision,
            queueNeedsBuild: nextQueueNeedsBuild
        )
        let revisionedCommands = commands.map { $0.withRevision(revision) }
        return QueueEngineReduction(nextState: nextState, transportCommands: revisionedCommands, wasNoOp: false)
    }
}
