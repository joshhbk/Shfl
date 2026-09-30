import Combine
import Foundation
import MusicKit

/// The real `MusicPlayerSurface`: MusicKit's shared application player.
final class ApplicationPlayerSurface: MusicPlayerSurface {
    private let player = ApplicationMusicPlayer.shared

    func installQueue(_ songs: [Song], startingAt currentSongID: String) async throws -> [Song] {
        let ids = songs.map { MusicItemID($0.id) }
        var request = MusicLibraryRequest<MusicKit.Song>()
        request.limit = ids.count
        request.filter(matching: \.id, memberOf: ids)
        let response = try await request.response()

        let itemsById = Dictionary(uniqueKeysWithValues: response.items.map { ($0.id.rawValue, $0) })
        let resolvedSongs = songs.filter { itemsById[$0.id] != nil }
        guard let startIndex = resolvedSongs.firstIndex(where: { $0.id == currentSongID }) else {
            throw PlaybackLoadError.currentSongMissing(currentSongID)
        }

        let entries = resolvedSongs
            .compactMap { itemsById[$0.id] }
            .map { MusicPlayer.Queue.Entry($0) }
        player.queue = ApplicationMusicPlayer.Queue(entries, startingAt: entries[startIndex])
        player.state.shuffleMode = .off
        return resolvedSongs
    }

    func clearQueue() {
        player.queue = []
    }

    var entryIDs: [String] {
        player.queue.entries.map(\.id)
    }

    var currentEntry: PlayerEntry? {
        guard let entry = player.queue.currentEntry else { return nil }
        guard case .song(let song) = entry.item else {
            return PlayerEntry(id: entry.id, song: nil, duration: 0)
        }
        return PlayerEntry(
            id: entry.id,
            song: Song(
                id: song.id.rawValue,
                title: song.title,
                artist: song.artistName,
                albumTitle: song.albumTitle ?? "",
                artworkURL: song.artwork?.url(width: 1200, height: 1200),
                playCount: song.playCount ?? 0,
                lastPlayedDate: song.lastPlayedDate
            ),
            duration: song.duration ?? 0
        )
    }

    var status: PlayerStatus {
        switch player.state.playbackStatus {
        case .playing: .playing
        case .paused: .paused
        case .stopped: .stopped
        case .interrupted: .interrupted
        case .seekingForward, .seekingBackward: .seeking
        @unknown default: .unknown
        }
    }

    var playbackTime: TimeInterval {
        get { player.playbackTime }
        set { player.playbackTime = newValue }
    }

    func prepareToPlay() async throws {
        try await player.prepareToPlay()
    }

    func play() async throws {
        try await player.play()
    }

    func pause() {
        player.pause()
    }

    func skipToNextEntry() async throws {
        try await player.skipToNextEntry()
    }

    func skipToPreviousEntry() async throws {
        try await player.skipToPreviousEntry()
    }

    var changes: AsyncStream<Void> {
        let stateChanges = player.state.objectWillChange.map { _ in () }
        let queueChanges = player.queue.objectWillChange.map { _ in () }
        let merged = Publishers.Merge(stateChanges, queueChanges)
        return AsyncStream { continuation in
            let task = Task { @MainActor in
                for await _ in merged.values {
                    continuation.yield()
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
