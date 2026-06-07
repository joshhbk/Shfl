import Foundation

// MARK: - Shared types

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

struct ArtistPage: Sendable {
    let artists: [Artist]
    let hasMore: Bool
}

struct PlaylistPage: Sendable {
    let playlists: [Playlist]
    let hasMore: Bool
}

enum QueueApplyPolicy: Sendable, Equatable {
    /// Ensure queue mutation ends in a playing state.
    case forcePlaying
    /// Ensure queue mutation ends in paused state.
    case forcePaused
}

// MARK: - MusicAuthorizing

/// Authorization-only interface. Consumers that only need auth gate depend on this.
protocol MusicAuthorizing: Sendable {
    /// Request authorization to access Apple Music
    func requestAuthorization() async -> Bool

    /// Check current authorization status
    var isAuthorized: Bool { get async }
}

// MARK: - LibraryCatalog

/// Library browsing and search interface. Consumers like pickers, lanes, autofill depend on this.
protocol LibraryCatalog: Sendable {
    /// Fetch songs from user's library with sorting and pagination
    func fetchLibrarySongs(
        sortedBy: SortOption,
        limit: Int,
        offset: Int
    ) async throws -> LibraryPage

    /// Search user's library for songs matching query with pagination
    func searchLibrarySongs(query: String, limit: Int, offset: Int) async throws -> LibraryPage

    /// Search user's library for artists matching query with pagination
    func searchLibraryArtists(query: String, limit: Int, offset: Int) async throws -> ArtistPage

    /// Search user's library for playlists matching query with pagination
    func searchLibraryPlaylists(query: String, limit: Int, offset: Int) async throws -> PlaylistPage

    /// Fetch artists from user's library with pagination
    func fetchLibraryArtists(limit: Int, offset: Int) async throws -> ArtistPage

    /// Fetch playlists from user's library with pagination
    func fetchLibraryPlaylists(limit: Int, offset: Int) async throws -> PlaylistPage

    /// Fetch songs by a specific artist name with pagination
    func fetchSongs(byArtist artistName: String, limit: Int, offset: Int) async throws -> LibraryPage

    /// Fetch songs from a specific playlist by ID with pagination
    func fetchSongs(byPlaylistId playlistId: String, limit: Int, offset: Int) async throws -> LibraryPage
}

// MARK: - PlaybackTransport

/// Playback transport interface. Consumers that queue songs and control playback depend on this.
protocol PlaybackTransport: Sendable {
    /// Set the playback queue with songs and shuffle them
    func setQueue(songs: [Song]) async throws

    /// Replace queue entries with explicit playback behavior.
    func replaceQueue(queue: [Song], startAtSongId: String?, policy: QueueApplyPolicy) async throws

    /// Start playback
    func play() async throws

    /// Pause playback
    func pause() async

    /// Pause playback synchronously (no await). Used when immediate audio stop is critical.
    func pauseImmediately()

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
    var currentSongId: String? { get }

    /// Number of entries in the MusicKit transport queue (best-effort snapshot).
    var transportQueueEntryCount: Int { get }
}

// MARK: - Combined typealias (backward compat)

/// Combined interface for consumers that need all three capabilities.
typealias MusicService = MusicAuthorizing & LibraryCatalog & PlaybackTransport