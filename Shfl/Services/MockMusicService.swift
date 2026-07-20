import Foundation

final class MockMusicService: MusicService {
    var isAuthorized: Bool { true }

    var playbackEvents: AsyncStream<PlaybackEvent> {
        AsyncStream { continuation in
            continuation.yield(.stateChanged(.empty))
        }
    }

    var currentPlaybackTime: TimeInterval { 0 }
    var currentSongDuration: TimeInterval { 180 }
    var currentSongId: String? { nil }
    func requestAuthorization() async -> Bool { true }

    func fetchLibrarySongs(
        sortedBy: SortOption,
        limit: Int,
        offset: Int
    ) async throws -> LibraryPage {
        LibraryPage(songs: [], hasMore: false)
    }

    func searchLibrarySongs(query: String, limit: Int, offset: Int) async throws -> LibraryPage {
        LibraryPage(songs: [], hasMore: false)
    }

    func searchLibraryArtists(query: String, limit: Int, offset: Int) async throws -> ArtistPage {
        ArtistPage(artists: [], hasMore: false)
    }

    func searchLibraryPlaylists(query: String, limit: Int, offset: Int) async throws -> PlaylistPage {
        PlaylistPage(playlists: [], hasMore: false)
    }

    func fetchLibraryArtists(limit: Int, offset: Int) async throws -> ArtistPage {
        ArtistPage(artists: [], hasMore: false)
    }

    func fetchLibraryPlaylists(limit: Int, offset: Int) async throws -> PlaylistPage {
        PlaylistPage(playlists: [], hasMore: false)
    }

    func fetchSongs(byArtist artistName: String, limit: Int, offset: Int) async throws -> LibraryPage {
        LibraryPage(songs: [], hasMore: false)
    }

    func fetchSongs(byPlaylistId playlistId: String, limit: Int, offset: Int) async throws -> LibraryPage {
        LibraryPage(songs: [], hasMore: false)
    }

    func load(_ request: PlaybackLoadRequest) async throws {}
    func play() async throws {}
    func pause() async {}
    func skipToNext() async throws {}
    func skipToPrevious() async throws {}
    func restartOrSkipToPrevious() async throws {}
    func seek(to time: TimeInterval) {}
    func clear() async {}
}
