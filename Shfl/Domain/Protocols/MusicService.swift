import Foundation

enum SortOption: String, CaseIterable, Sendable {
    case mostPlayed
    case recentlyPlayed
    case recentlyAdded
    case alphabetical

    var displayName: String {
        switch self {
        case .mostPlayed: "Most Played"
        case .recentlyPlayed: "Recently Played"
        case .recentlyAdded: "Recently Added"
        case .alphabetical: "Alphabetical"
        }
    }
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

    /// Search user's library for songs matching query with pagination
    func searchLibrarySongs(query: String, limit: Int, offset: Int) async throws -> LibraryPage

    /// Set the playback queue with songs and shuffle them
    func setQueue(songs: [Song]) async throws

    /// Insert songs into the existing queue without disrupting playback
    func insertIntoQueue(songs: [Song]) async throws

    /// Replace the upcoming queue without disrupting the current song's playback position
    func replaceUpcomingQueue(with songs: [Song], currentSong: Song) async throws

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

    /// Seek to a specific time in the current song
    func seek(to time: TimeInterval)

    /// Get current playback state (observable)
    var playbackStateStream: AsyncStream<PlaybackState> { get }

    /// Current playback time in seconds
    var currentPlaybackTime: TimeInterval { get }

    /// Duration of current song in seconds (0 if nothing playing)
    var currentSongDuration: TimeInterval { get }

    /// ID of the currently playing song (nil if nothing playing)
    /// This reads directly from MusicKit, not from cached state
    var currentSongId: String? { get }
}
