import Combine
import Foundation
import MusicKit

final class AppleMusicService: MusicService, @unchecked Sendable {
    private let player = ApplicationMusicPlayer.shared
    private var stateObservationTask: Task<Void, Never>?
    private var continuation: AsyncStream<PlaybackState>.Continuation?

    var playbackStateStream: AsyncStream<PlaybackState> {
        AsyncStream { [weak self] continuation in
            self?.continuation = continuation
            self?.startObservingPlaybackState()
        }
    }

    var isAuthorized: Bool {
        get async {
            MusicAuthorization.currentStatus == .authorized
        }
    }

    func requestAuthorization() async -> Bool {
        let status = await MusicAuthorization.request()
        return status == .authorized
    }

    func searchLibrary(query: String) async throws -> [Song] {
        var request = MusicCatalogSearchRequest(term: query, types: [MusicKit.Song.self])
        request.limit = 25

        let response = try await request.response()
        return response.songs.map { musicKitSong in
            Song(
                id: musicKitSong.id.rawValue,
                title: musicKitSong.title,
                artist: musicKitSong.artistName,
                albumTitle: musicKitSong.albumTitle ?? "",
                artworkURL: musicKitSong.artwork?.url(width: 300, height: 300)
            )
        }
    }

    func setQueue(songs: [Song]) async throws {
        // Convert our Song models back to MusicKit songs
        let ids = songs.map { MusicItemID($0.id) }
        let request = MusicCatalogResourceRequest<MusicKit.Song>(matching: \.id, memberOf: ids)
        let response = try await request.response()

        let queue = ApplicationMusicPlayer.Queue(for: response.items, startingAt: nil)
        player.queue = queue
        player.state.shuffleMode = .songs
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

    private func startObservingPlaybackState() {
        stateObservationTask?.cancel()
        stateObservationTask = Task { [weak self] in
            guard let self else { return }

            // Initial state
            self.emitCurrentState()

            // Observe state changes
            for await _ in self.player.state.objectWillChange.values {
                self.emitCurrentState()
            }
        }
    }

    private func emitCurrentState() {
        let state = mapPlaybackState()
        continuation?.yield(state)
    }

    private func mapPlaybackState() -> PlaybackState {
        guard let currentEntry = player.queue.currentEntry else {
            return .empty
        }

        guard case .song(let musicKitSong) = currentEntry.item else {
            return .stopped
        }

        let song = Song(
            id: musicKitSong.id.rawValue,
            title: musicKitSong.title,
            artist: musicKitSong.artistName,
            albumTitle: musicKitSong.albumTitle ?? "",
            artworkURL: musicKitSong.artwork?.url(width: 300, height: 300)
        )

        switch player.state.playbackStatus {
        case .playing:
            return .playing(song)
        case .paused:
            return .paused(song)
        case .stopped:
            return .stopped
        case .interrupted:
            return .paused(song)
        case .seekingForward, .seekingBackward:
            return .playing(song)
        @unknown default:
            return .stopped
        }
    }
}
