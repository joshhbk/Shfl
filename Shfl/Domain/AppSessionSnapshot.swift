import Foundation

struct AppSessionSnapshot: Equatable, Sendable {
    let songs: [Song]
    let playback: PlaybackSessionSnapshot?

    static let empty = AppSessionSnapshot(songs: [], playback: nil)
}

struct PlaybackSessionSnapshot: Equatable, Sendable {
    let currentSongId: String?
    let playbackPosition: TimeInterval
    let savedAt: Date
    let queueOrder: [String]
    let playedSongIds: Set<String>
}
