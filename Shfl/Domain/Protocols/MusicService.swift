import Foundation

protocol MusicService: Sendable {
    /// Request authorization to access Apple Music
    func requestAuthorization() async -> Bool

    /// Check current authorization status
    var isAuthorized: Bool { get async }

    /// Search for songs in user's library
    func searchLibrary(query: String) async throws -> [Song]

    /// Set the playback queue with songs and shuffle them
    func setQueue(songs: [Song]) async throws

    /// Start playback
    func play() async throws

    /// Pause playback
    func pause() async

    /// Skip to next song
    func skipToNext() async throws

    /// Get current playback state (observable)
    var playbackStateStream: AsyncStream<PlaybackState> { get }
}
