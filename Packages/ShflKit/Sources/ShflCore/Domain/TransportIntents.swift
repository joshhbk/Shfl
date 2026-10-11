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
        /// The draft has changed since the session that's playing was shuffled.
        case changedDraft(songCount: Int)
        /// Nothing is playing.
        case draft(songCount: Int)
        case autofillAndShuffle(songCount: Int)
    }

    public let play: Play
    public let shuffle: Shuffle

    enum SessionState: Equatable, Sendable {
        case none
        case active(isPlaying: Bool, draftDiffers: Bool)
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
        case (.active(_, let draftDiffers), let count):
            shuffle = draftDiffers ? .changedDraft(songCount: count) : .again
        }
    }
}
