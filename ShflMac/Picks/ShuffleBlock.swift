import ShflCore
import ShflDesign
import SwiftUI

/// The only way from your picks to what plays: what the next shuffle would change, its style, and Shuffle.
struct ShuffleBlock: View {
    @Environment(ListeningSessionHost.self) private var sessionHost
    @Environment(DraftEditing.self) private var drafting

    var body: some View {
        let shuffle = sessionHost.intents.shuffle
        let algorithm = drafting.draft.algorithm
        VStack(alignment: .leading, spacing: Spacing.s8) {
            StatusLine("Next shuffle") {
                Text(shuffle.status)
                    .fontWeight(shuffle.differsFromPlaying ? .semibold : .regular)
                    .foregroundStyle(shuffle.differsFromPlaying ? AnyShapeStyle(.accentText) : AnyShapeStyle(.secondary))
            }
            Menu {
                ShuffleStyleItems(draft: drafting.draft)
            } label: {
                FieldLabel(algorithm.displayName)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fieldHighlight(shuffle.isStyleChange)
            .accessibilityLabel("Shuffle style")
            .accessibilityValue(algorithm.displayName)
            .accessibilityIdentifier("mac.picks.shuffleStyle")
            Text(algorithm.summary)
                .font(.secondaryText)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 32, alignment: .top)
            ShuffleButton(intent: shuffle, algorithm: algorithm)
        }
        .padding(.top, Spacing.s14)
        .overlay(alignment: .top) { Rectangle().fill(.hairline).frame(height: 1) }
    }
}

private struct ShuffleButton: View {
    let intent: TransportIntents.Shuffle
    let algorithm: ShuffleAlgorithm

    @Environment(ListeningSessionHost.self) private var sessionHost

    var body: some View {
        let button = Button {
            Task { await sessionHost.startFreshShuffle(autofillingEmptyDraft: true) }
        } label: {
            HStack(spacing: Spacing.s8) {
                Text(intent.title)
                Image(systemName: "arrow.right")
            }
            .frame(maxWidth: .infinity)
        }
        .disabled(sessionHost.isStartingSession)
        .accessibilityHint("Starts a new session from your picks, using \(algorithm.displayName).")
        .accessibilityIdentifier("mac.picks.shuffle")

        if intent == .again {
            button.buttonStyle(.accentOutline)
        } else {
            button.buttonStyle(.primary)
        }
    }
}

/// The shuffle styles as a checked list, for the field's menu and the Picks menu.
struct ShuffleStyleItems: View {
    let draft: SessionDraftStore

    var body: some View {
        Picker("Shuffle Style", selection: Binding(get: { draft.algorithm }, set: { draft.stage($0) })) {
            ForEach(ShuffleAlgorithm.allCases, id: \.self) { algorithm in
                Text(algorithm.displayName).tag(algorithm)
            }
        }
        .pickerStyle(.inline)
        .labelsHidden()
    }
}

private extension TransportIntents.Shuffle {
    var status: String {
        switch self {
        case .again: "Matches what’s playing"
        case .changedDraft: "Picks have changed"
        case .changedStyle(let playing): "Playing uses \(playing.displayName)"
        case .draft: "Nothing playing yet"
        case .autofillAndShuffle: "No picks yet"
        }
    }

    var differsFromPlaying: Bool {
        switch self {
        case .changedDraft, .changedStyle: true
        case .again, .draft, .autofillAndShuffle: false
        }
    }

    var isStyleChange: Bool {
        if case .changedStyle = self { true } else { false }
    }
}

private extension ShuffleAlgorithm {
    var summary: String {
        switch self {
        case .pureRandom: "Picks at random. A song can repeat before others play."
        case .noRepeat: "Plays every song once before any repeats."
        case .weightedByRecency: "Favours songs you haven’t heard in a while."
        case .weightedByPlayCount: "Favours songs with fewer plays."
        case .artistSpacing: "Keeps the same artist from playing back to back."
        }
    }
}
