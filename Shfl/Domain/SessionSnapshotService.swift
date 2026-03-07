import Foundation

@MainActor
final class SessionSnapshotService {
    private let songRepository: SongRepository
    private let playbackStateRepository: PlaybackStateRepository

    init(
        songRepository: SongRepository,
        playbackStateRepository: PlaybackStateRepository
    ) {
        self.songRepository = songRepository
        self.playbackStateRepository = playbackStateRepository
    }

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

    func isPlaybackStateStale(_ snapshot: PlaybackSessionSnapshot) -> Bool {
        playbackStateRepository.isStateStale(snapshot)
    }
}
