import Foundation

struct QueueEngineState: Equatable, Sendable {
    var queueState: QueueState
    var playbackState: PlaybackState
    var revision: Int
    var queueNeedsBuild: Bool
}

enum TransportCommand: Sendable {
    case setQueue(songs: [Song], revision: Int)
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
    case seedSongs([Song])
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
    case resyncActiveAddTransport
    case syncDeferredTransport
    case recoverFromStaleTransport
    case recoverFromInvariantViolation
    case setQueueNeedsBuild(Bool)
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

    var requiresActiveTransportSync: Bool {
        nextState.playbackState.isActive && !transportCommands.isEmpty
    }
}

enum QueueEngineReducer {
    private static func appendReplaceQueueCommand(
        state: QueueEngineState,
        queueState: QueueState,
        commands: inout [TransportCommand]
    ) {
        let policy: QueueApplyPolicy = state.playbackState.isPlaying ? .forcePlaying : .forcePaused
        commands.append(
            .replaceQueue(
                queue: queueState.queueOrder,
                startAtSongId: queueState.currentSongId,
                policy: policy,
                revision: 0
            )
        )
    }

    private static func rebuildUpcomingAndAppendReplaceCommand(
        state: QueueEngineState,
        queueState: inout QueueState,
        commands: inout [TransportCommand],
        algorithm: ShuffleAlgorithm
    ) {
        let preferredCurrentSongId = state.playbackState.currentSongId ?? state.queueState.currentSongId
        queueState = queueState.reshuffledUpcoming(
            with: algorithm,
            preferredCurrentSongId: preferredCurrentSongId
        )
        appendReplaceQueueCommand(state: state, queueState: queueState, commands: &commands)
    }

    private static func applyActiveAddRebuildPolicy(
        state: QueueEngineState,
        queueState: inout QueueState,
        queueNeedsBuild: inout Bool,
        commands: inout [TransportCommand],
        algorithm: ShuffleAlgorithm
    ) {
        if state.playbackState.isActive && state.queueState.hasQueue {
            // Reshuffle the domain queue so the new song is correctly placed in upcoming,
            // but defer the transport sync to the next natural boundary (song transition,
            // pause, or resume) to avoid an audible playback interruption from rebuilding
            // the MusicKit queue mid-song.
            let preferredCurrentSongId = state.playbackState.currentSongId ?? state.queueState.currentSongId
            queueState = queueState.reshuffledUpcoming(
                with: algorithm,
                preferredCurrentSongId: preferredCurrentSongId
            )
            queueNeedsBuild = true
            return
        }

        if state.playbackState.isActive {
            // Active playback can briefly exist before queue build is complete; defer until queue exists.
            queueNeedsBuild = true
        } else if state.queueState.hasQueue {
            // Queue exists but has not yet incorporated new pool mutations.
            queueNeedsBuild = true
        }
    }

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

            applyActiveAddRebuildPolicy(
                state: state,
                queueState: &nextQueueState,
                queueNeedsBuild: &nextQueueNeedsBuild,
                commands: &commands,
                algorithm: nextQueueState.algorithm
            )

        case .seedSongs(let songs):
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

            applyActiveAddRebuildPolicy(
                state: state,
                queueState: &nextQueueState,
                queueNeedsBuild: &nextQueueNeedsBuild,
                commands: &commands,
                algorithm: algorithm ?? nextQueueState.algorithm
            )

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

        case .resyncActiveAddTransport:
            guard state.playbackState.isActive && state.queueState.hasQueue else {
                return QueueEngineReduction(nextState: state, transportCommands: [], wasNoOp: true)
            }
            rebuildUpcomingAndAppendReplaceCommand(
                state: state,
                queueState: &nextQueueState,
                commands: &commands,
                algorithm: state.queueState.algorithm
            )
            nextQueueNeedsBuild = false

        case .syncDeferredTransport:
            guard state.playbackState.isActive && state.queueState.hasQueue else {
                return QueueEngineReduction(nextState: state, transportCommands: [], wasNoOp: true)
            }
            appendReplaceQueueCommand(state: state, queueState: state.queueState, commands: &commands)
            nextQueueNeedsBuild = false

        case .recoverFromStaleTransport:
            nextQueueNeedsBuild = true
            if case .loading = state.playbackState {
                if let current = state.queueState.currentSong {
                    nextPlaybackState = .paused(current)
                } else if state.queueState.isEmpty {
                    nextPlaybackState = .empty
                } else {
                    nextPlaybackState = .stopped
                }
            }

        case .recoverFromInvariantViolation:
            nextQueueNeedsBuild = true

        case .setQueueNeedsBuild(let value):
            nextQueueNeedsBuild = value

        case .playbackResolution(let resolution):
            // Observer-level normalization already handles transient stop/empty transport blips.
            // Reducer-level rebuild decisions here should react only to durable error states.
            if resolution.shouldUpdateCurrentSong, let songId = resolution.resolvedSongId {
                nextQueueState = nextQueueState.settingCurrentSong(id: songId)
            }
            if let playedId = resolution.songIdToMarkPlayed {
                nextQueueState = nextQueueState.markingAsPlayed(id: playedId)
            }
            if resolution.shouldClearHistory {
                nextQueueState = nextQueueState.clearingPlayedHistory()
                if !nextQueueState.isEmpty,
                   case .error = resolution.resolvedState {
                    // Only force rebuild for explicit playback errors.
                    // Stop/empty transitions can be transient transport artifacts and should not
                    // reshuffle away the current listening context on pause/resume.
                    nextQueueNeedsBuild = true
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
