import Foundation

enum SortOption: Sendable {
    case mostPlayed
    case recentlyPlayed
    case recentlyAdded
    case alphabetical
}

struct LibraryPage: Sendable {
    let songs: [Song]
    let hasMore: Bool
}

protocol MusicService: Sendable {
    /// Request authorization to access Apple Music
    func requestAuthorization() async -> Bool

    /// Check current authorization status
    var isAuthorized: Bool { get async }

    /// Fetch songs from user's library with sorting and pagination
    func fetchLibrarySongs(
        sortedBy: SortOption,
        limit: Int,
        offset: Int
    ) async throws -> LibraryPage

    /// Search user's library for songs matching query
    func searchLibrarySongs(query: String) async throws -> [Song]

    /// Set the playback queue with songs and shuffle them
    func setQueue(songs: [Song]) async throws

    /// Start playback
    func play() async throws

    /// Pause playback
    func pause() async

    /// Skip to next song
    func skipToNext() async throws

    /// Skip to previous song
    func skipToPrevious() async throws

    /// Restart current song from beginning, or skip to previous if near start
    func restartOrSkipToPrevious() async throws

    /// Get current playback state (observable)
    var playbackStateStream: AsyncStream<PlaybackState> { get }

    /// Current playback time in seconds
    var currentPlaybackTime: TimeInterval { get }

    /// Duration of current song in seconds (0 if nothing playing)
    var currentSongDuration: TimeInterval { get }
}
