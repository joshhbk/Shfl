import Foundation
@testable import ShflAppleMusic
@testable import ShflCore

/// A stand-in for MusicKit's application player that reproduces the behaviour
/// `MusicKitTransport` exists to absorb:
/// - Starting playback replaces every entry ID, and entries report catalog
///   song IDs instead of the library IDs that were queued.
/// - Moving between entries passes through a moment with no current entry and
///   a stopped player.
/// - Finishing the final entry leaves it loaded with the player stopped.
@MainActor
final class FakeMusicPlayer: MusicPlayerSurface {
    struct QueuedEntry {
        var id: String
        let song: Song
    }

    /// Songs that no longer resolve in the library and are dropped on install.
    var unresolvableSongIDs: Set<String> = []
    var songDuration: TimeInterval = 180

    private(set) var queue: [QueuedEntry] = []
    private(set) var currentIndex: Int?
    private(set) var status: PlayerStatus = .stopped
    var playbackTime: TimeInterval = 0

    private var hasReplacedIdentifiers = false
    private var generation = 0
    private var continuations: [UUID: AsyncStream<Void>.Continuation] = [:]

    // MARK: - MusicPlayerSurface

    func installQueue(_ songs: [Song], startingAt currentSongID: String) async throws -> [Song] {
        let resolved = songs.filter { !unresolvableSongIDs.contains($0.id) }
        guard let startIndex = resolved.firstIndex(where: { $0.id == currentSongID }) else {
            throw PlaybackLoadError.currentSongMissing(currentSongID)
        }
        generation += 1
        queue = resolved.enumerated().map { index, song in
            QueuedEntry(id: "entry-\(generation)-\(index)", song: song)
        }
        currentIndex = startIndex
        hasReplacedIdentifiers = false
        await notify()
        return resolved
    }

    func clearQueue() {
        queue = []
        currentIndex = nil
        yieldChange()
    }

    var entryIDs: [String] {
        queue.map(\.id)
    }

    var currentEntry: PlayerEntry? {
        guard let currentIndex, queue.indices.contains(currentIndex) else { return nil }
        let entry = queue[currentIndex]
        return PlayerEntry(id: entry.id, song: reportedSong(entry.song), duration: songDuration)
    }

    func prepareToPlay() async throws {}

    func play() async throws {
        guard currentIndex != nil else { return }
        if !hasReplacedIdentifiers {
            hasReplacedIdentifiers = true
            for index in queue.indices {
                queue[index].id = "replaced-\(queue[index].id)"
            }
        }
        status = .playing
        await notify()
    }

    func pause() {
        guard currentIndex != nil else { return }
        status = .paused
        yieldChange()
    }

    func skipToNextEntry() async throws {
        try await advance()
    }

    func skipToPreviousEntry() async throws {
        guard let currentIndex else { return }
        await moveBetweenEntries(to: max(0, currentIndex - 1))
    }

    var changes: AsyncStream<Void> {
        AsyncStream { continuation in
            let id = UUID()
            continuations[id] = continuation
            continuation.onTermination = { _ in
                Task { @MainActor [weak self] in
                    self?.continuations.removeValue(forKey: id)
                }
            }
        }
    }

    // MARK: - Driving playback

    /// The current song plays to its end.
    func finishCurrentEntry() async {
        try? await advance()
    }

    /// MusicKit briefly reports the player stopped with the entry still
    /// loaded, then carries on playing.
    func stutter() async {
        status = .stopped
        await notify()
        status = .playing
        await notify()
    }

    // MARK: - Private

    private func advance() async throws {
        guard let currentIndex else { return }
        if currentIndex + 1 < queue.count {
            await moveBetweenEntries(to: currentIndex + 1)
        } else {
            playbackTime = 0
            status = .stopped
            await notify()
        }
    }

    private func moveBetweenEntries(to index: Int) async {
        let wasPlaying = status == .playing
        currentIndex = nil
        status = .stopped
        await notify()

        currentIndex = index
        playbackTime = 0
        status = wasPlaying ? .playing : .paused
        await notify()
    }

    private func reportedSong(_ song: Song) -> Song {
        guard hasReplacedIdentifiers else { return song }
        return Song(
            id: "catalog-\(song.id)",
            title: song.title,
            artist: song.artist,
            albumTitle: song.albumTitle,
            artworkURL: nil,
            playCount: song.playCount,
            lastPlayedDate: song.lastPlayedDate
        )
    }

    private func yieldChange() {
        for continuation in continuations.values {
            continuation.yield()
        }
    }

    /// Publishes a change and lets observers read this exact state before the
    /// next mutation, as MusicKit's intermediate states are visible in practice.
    private func notify() async {
        yieldChange()
        for _ in 0..<30 {
            await Task.yield()
        }
    }
}

/// Holds the transport's end-of-session confirmation until the test releases it.
@MainActor
final class ManualDelay {
    private var waiters: [CheckedContinuation<Void, Never>] = []

    var pendingCount: Int { waiters.count }

    func wait() async {
        await withCheckedContinuation { waiters.append($0) }
    }

    func releaseAll() {
        let released = waiters
        waiters = []
        released.forEach { $0.resume() }
    }
}
