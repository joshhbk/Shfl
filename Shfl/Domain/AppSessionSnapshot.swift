import Foundation

nonisolated struct AppSessionSnapshot: Equatable, Sendable {
    let songs: [Song]
    let playback: PlaybackSessionSnapshot?

    static let empty = AppSessionSnapshot(songs: [], playback: nil)
}

nonisolated struct PlaybackSessionSnapshot: Equatable, Sendable {
    let currentSongId: String?
    let playbackPosition: TimeInterval
    let savedAt: Date
    let queueOrder: [String]
    let playedSongIds: Set<String>
    let algorithm: ShuffleAlgorithm
    let seed: UInt64?

    init(
        currentSongId: String?,
        playbackPosition: TimeInterval,
        savedAt: Date,
        queueOrder: [String],
        playedSongIds: Set<String>,
        algorithm: ShuffleAlgorithm = .noRepeat,
        seed: UInt64? = nil
    ) {
        self.currentSongId = currentSongId
        self.playbackPosition = playbackPosition
        self.savedAt = savedAt
        self.queueOrder = queueOrder
        self.playedSongIds = playedSongIds
        self.algorithm = algorithm
        self.seed = seed
    }
}
