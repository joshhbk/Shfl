import Foundation

/// One committed playback change. Every subscriber receives the same ordered
/// values; session and position belong to this change, not a later player state.
nonisolated struct PlaybackTransition: Sendable {
    let observedAt = Date()
    let state: PlaybackState
    let session: ListeningSession?
    let playbackTime: TimeInterval
    /// Nil for status-only changes such as pausing or resuming the same song.
    let songTransition: SongTransition?
}

/// Song selection and first playback are separate lifecycle events: a paused
/// restore or loading state can select a song before it starts playing.
nonisolated enum SongTransition: Equatable, Sendable {
    case selected(Song)
    case started(Song)
    case selectedAndStarted(Song)
    case cleared
}
