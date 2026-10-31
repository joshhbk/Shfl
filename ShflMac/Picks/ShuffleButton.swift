import ShflCore
import ShflDesign
import SwiftUI

/// The only way from your picks to what plays.
struct ShuffleButton: View {
    @Environment(ListeningSessionHost.self) private var sessionHost
    @Environment(DraftEditing.self) private var drafting

    var body: some View {
        let intent = sessionHost.intents.shuffle
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
        .accessibilityHint("Starts a new session from your picks, using \(drafting.draft.algorithm.displayName).")
        .accessibilityIdentifier("mac.picks.shuffle")

        if intent == .again {
            button.buttonStyle(.accentOutline)
        } else {
            button.buttonStyle(.primary)
        }
    }
}
