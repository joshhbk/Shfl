import Foundation

final class MockMusicService: MusicService, @unchecked Sendable {
    var isAuthorized: Bool { true }

    var playbackStateStream: AsyncStream<PlaybackState> {
        AsyncStream { continuation in
            continuation.yield(.empty)
        }
    }

    var currentPlaybackTime: TimeInterval { 0 }
    var currentSongDuration: TimeInterval { 180 }

    func requestAuthorization() async -> Bool { true }

    func fetchLibrarySongs(
        sortedBy: SortOption,
        limit: Int,
        offset: Int
    ) async throws -> LibraryPage {
        LibraryPage(songs: [], hasMore: false)
    }

    func searchLibrarySongs(query: String) async throws -> [Song] {
        []
    }

    func setQueue(songs: [Song]) async throws {}
    func play() async throws {}
    func pause() async {}
    func skipToNext() async throws {}
    func skipToPrevious() async throws {}
    func restartOrSkipToPrevious() async throws {}
}
