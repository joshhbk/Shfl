import Foundation

// MARK: - Shared types

public enum SortOption: String, CaseIterable, Sendable {
    case mostPlayed
    case recentlyPlayed
    case recentlyAdded
    case alphabetical

    public var displayName: String {
        switch self {
        case .mostPlayed: "Most Played"
        case .recentlyPlayed: "Recently Played"
        case .recentlyAdded: "Recently Added"
        case .alphabetical: "Alphabetical"
        }
    }
}

public nonisolated struct LibraryPage: Sendable {
    public let songs: [Song]
    public let hasMore: Bool

    public init(songs: [Song], hasMore: Bool) {
        self.songs = songs
        self.hasMore = hasMore
    }
}

public nonisolated struct ArtistPage: Sendable {
    public let artists: [Artist]
    public let hasMore: Bool

    public init(artists: [Artist], hasMore: Bool) {
        self.artists = artists
        self.hasMore = hasMore
    }
}

public nonisolated struct PlaylistPage: Sendable {
    public let playlists: [Playlist]
    public let hasMore: Bool

    public init(playlists: [Playlist], hasMore: Bool) {
        self.playlists = playlists
        self.hasMore = hasMore
    }
}

public nonisolated struct PlaybackLoadRequest: Sendable, Equatable {
    let sessionID: UUID
    public let queue: [Song]
    public let currentSongID: String
    public let playbackPosition: TimeInterval
    public let autoplay: Bool
}

public nonisolated enum PlaybackLoadError: LocalizedError, Sendable, Equatable {
    case emptyQueue
    case currentSongMissing(String)

    public var errorDescription: String? {
        switch self {
        case .emptyQueue:
            return "Cannot load an empty listening session."
        case .currentSongMissing(let songID):
            return "The selected song \(songID) is not in the listening session."
        }
    }
}

public nonisolated enum PlaybackEvent: Sendable, Equatable {
    case stateChanged(PlaybackState)
    case sessionEnded
}

// MARK: - MusicAuthorizing

/// Authorization-only interface. Consumers that only need auth gate depend on this.
public nonisolated protocol MusicAuthorizing: Sendable {
    /// Request authorization to access Apple Music
    func requestAuthorization() async -> Bool

    /// Check current authorization status
    var isAuthorized: Bool { get async }
}

// MARK: - LibraryCatalog

/// Library browsing and search interface. Consumers like pickers, lanes, autofill depend on this.
public nonisolated protocol LibraryCatalog: Sendable {
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
///
/// The synchronous requirements are main-actor because MusicKit's player state
/// may only be read there. The async ones stay nonisolated so an actor can
/// adopt the protocol.
public nonisolated protocol PlaybackTransport: Sendable {
    /// Atomically install one immutable listening session.
    func load(_ request: PlaybackLoadRequest) async throws

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
    @MainActor
    func seek(to time: TimeInterval)

    /// Clear the installed session and stop playback.
    func clear() async

    /// Normalized transport events. Session completion is explicit.
    @MainActor
    var playbackEvents: AsyncStream<PlaybackEvent> { get }

    /// Current playback time in seconds
    @MainActor
    var currentPlaybackTime: TimeInterval { get }

    /// Duration of current song in seconds (0 if nothing playing)
    @MainActor
    var currentSongDuration: TimeInterval { get }

    /// ID of the currently playing song (nil if nothing playing)
    @MainActor
    var currentSongId: String? { get }

}

// MARK: - Combined typealias (backward compat)

/// Combined interface for consumers that need all three capabilities.
public typealias MusicService = MusicAuthorizing & LibraryCatalog & PlaybackTransport
