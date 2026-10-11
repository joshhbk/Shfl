import Foundation

/// What Play and Shuffle would do right now, so every control that offers them labels them the same way.
public nonisolated struct TransportIntents: Equatable, Sendable {
    public enum Play: Equatable, Sendable {
        case pause
        case resume
        case shuffleDraft(songCount: Int)
        case autofillAndShuffle(songCount: Int)
    }

    public enum Shuffle: Equatable, Sendable {
        /// The draft matches the session that's playing.
        case again
        /// The draft's songs have changed since the session that's playing was shuffled.
        case changedDraft(songCount: Int)
        /// Only the shuffle style has changed since the session that's playing was shuffled.
        case changedStyle(playing: ShuffleAlgorithm)
        /// Nothing is playing.
        case draft(songCount: Int)
        case autofillAndShuffle(songCount: Int)
    }

    public let play: Play
    public let shuffle: Shuffle

    enum SessionState: Equatable, Sendable {
        case none
        case active(isPlaying: Bool, pending: PendingChange)
    }

    enum PendingChange: Equatable, Sendable {
        case none
        case songs
        case style(playing: ShuffleAlgorithm)
    }

    init(session: SessionState, draftSongCount: Int, autofillSongCount: Int) {
        switch (session, draftSongCount) {
        case (.active(let isPlaying, _), _):
            play = isPlaying ? .pause : .resume
        case (.none, 0):
            play = .autofillAndShuffle(songCount: autofillSongCount)
        case (.none, let count):
            play = .shuffleDraft(songCount: count)
        }

        switch (session, draftSongCount) {
        case (_, 0):
            shuffle = .autofillAndShuffle(songCount: autofillSongCount)
        case (.none, let count):
            shuffle = .draft(songCount: count)
        case (.active(_, .none), _):
            shuffle = .again
        case (.active(_, .songs), let count):
            shuffle = .changedDraft(songCount: count)
        case (.active(_, .style(let playing)), _):
            shuffle = .changedStyle(playing: playing)
        }
    }
}
