import Foundation

/// One committed playback change. Every subscriber receives the same ordered
/// values; session and position belong to this change, not a later player state.
nonisolated struct PlaybackTransition: Sendable {
    let state: PlaybackState
    let session: ListeningSession?
    let playbackTime: TimeInterval
    let songChanged: Bool
    /// First playing state for this song in this session, including after a
    /// paused restore or loading state. Pause/resume does not start a new song.
    let startsSong: Bool
}
