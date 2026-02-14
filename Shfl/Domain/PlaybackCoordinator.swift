import Foundation

@MainActor
final class PlaybackCoordinator {
    private let player: ShufflePlayer
    private let appSettings: AppSettings

    /// Serializes command execution without manual continuation management.
    private var commandQueue: Task<Void, Never> = Task { }

    init(player: ShufflePlayer, appSettings: AppSettings) {
        self.player = player
        self.appSettings = appSettings
    }

    private func enqueue<T>(_ operation: @escaping @MainActor () async throws -> T) async throws -> T {
        let previous = self.commandQueue
        let task = Task<T, Error> { @MainActor in
            await previous.value
            return try await operation()
        }
        self.commandQueue = Task {
            _ = await task.result
        }
        return try await task.value
    }

    private func enqueue<T>(_ operation: @escaping @MainActor () async -> T) async -> T {
        let previous = self.commandQueue
        let task = Task<T, Never> { @MainActor in
            await previous.value
            return await operation()
        }
        self.commandQueue = Task {
            _ = await task.value
        }
        return await task.value
    }

    func seedSongs(_ songs: [Song]) async throws {
        try await enqueue { [self] in
            try self.player.seedSongs(songs)
        }
    }

    func prepareQueue() async throws {
        try await enqueue { [self] in
            try await self.player.prepareQueue(algorithm: self.appSettings.shuffleAlgorithm)
        }
    }

    func play() async throws {
        try await enqueue { [self] in
            try await self.player.play(algorithm: self.appSettings.shuffleAlgorithm)
        }
    }

    func pause() async {
        await enqueue { [self] in
            await self.player.pause()
        }
    }

    func togglePlayback() async throws {
        try await enqueue { [self] in
            try await self.player.togglePlayback(algorithm: self.appSettings.shuffleAlgorithm)
        }
    }

    func skipToNext() async throws {
        try await enqueue { [self] in
            try await self.player.skipToNext()
        }
    }

    func restartOrSkipToPrevious() async throws {
        try await enqueue { [self] in
            try await self.player.restartOrSkipToPrevious()
        }
    }

    func addSong(_ song: Song) async throws {
        try await enqueue { [self] in
            try await self.player.addSong(song)
        }
    }

    func addSongsWithQueueRebuild(_ songs: [Song]) async throws {
        try await enqueue { [self] in
            try await self.player.addSongsWithQueueRebuild(songs, algorithm: self.appSettings.shuffleAlgorithm)
        }
    }

    func removeSong(id: String) async {
        await enqueue { [self] in
            await self.player.removeSong(id: id)
        }
    }

    func removeAllSongs() async {
        await enqueue { [self] in
            await self.player.removeAllSongs()
        }
    }

    func reshuffleAlgorithm(_ algorithm: ShuffleAlgorithm) async {
        await enqueue { [self] in
            await self.player.reshuffleWithNewAlgorithm(algorithm)
        }
    }

    func restoreSession(
        queueOrder: [String],
        currentSongId: String?,
        playedIds: Set<String>,
        playbackPosition: TimeInterval
    ) async -> Bool {
        await enqueue { [self] in
            await self.player.restoreSession(
                queueOrder: queueOrder,
                currentSongId: currentSongId,
                playedIds: playedIds,
                playbackPosition: playbackPosition
            )
        }
    }
}
