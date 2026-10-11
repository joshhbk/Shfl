import ShflCore

extension TransportIntents.Play {
    var title: String {
        switch self {
        case .pause: "Pause"
        case .resume, .shuffleDraft, .autofillAndShuffle: "Play"
        }
    }

    /// Spells out what Play will do when it does more than resume.
    var accessibilityHint: String? {
        switch self {
        case .pause, .resume: nil
        case .shuffleDraft(let count): "Shuffles the \(count) songs in your pool."
        case .autofillAndShuffle(let count): "Fills the pool with \(count) random songs, then shuffles."
        }
    }

    var systemImage: String {
        self == .pause ? "pause.fill" : "play.fill"
    }
}

extension TransportIntents.Shuffle {
    var title: String {
        switch self {
        case .again: "Shuffle Again"
        case .changedDraft: "Shuffle Now"
        case .draft(let count): count == 1 ? "Shuffle 1 Song" : "Shuffle \(count) Songs"
        case .autofillAndShuffle: "Autofill and Shuffle"
        }
    }
}
