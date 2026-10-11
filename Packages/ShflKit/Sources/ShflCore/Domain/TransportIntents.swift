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

    init(
        hasActiveSession: Bool,
        isPlaying: Bool,
        draftSongCount: Int,
        autofillSongCount: Int,
        draftDiffersFromSession: Bool
    ) {
        switch (hasActiveSession, draftSongCount) {
        case (true, _):
            play = isPlaying ? .pause : .resume
        case (false, 0):
            play = .autofillAndShuffle(songCount: autofillSongCount)
        case (false, let count):
            play = .shuffleDraft(songCount: count)
        }

        switch (hasActiveSession, draftSongCount) {
        case (_, 0):
            shuffle = .autofillAndShuffle(songCount: autofillSongCount)
        case (false, let count):
            shuffle = .draft(songCount: count)
        case (true, let count):
            shuffle = draftDiffersFromSession ? .changedDraft(songCount: count) : .again
        }
    }
}
