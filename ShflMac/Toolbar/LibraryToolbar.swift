import ShflCore
import SwiftUI

struct LibraryToolbar: ToolbarContent {
    var body: some ToolbarContent {
        ToolbarItem { AutofillButton() }
        ToolbarItem { ShuffleButton() }
    }
}

private struct AutofillButton: View {
    @Environment(DraftEditing.self) private var drafting

    var body: some View {
        Button("Autofill", systemImage: "wand.and.stars") {
            Task { await drafting.autofill() }
        }
        .help("Fill your picks with songs from your library")
        .disabled(!drafting.canAutofill)
        .accessibilityIdentifier("mac.toolbar.autofill")
    }
}

private struct ShuffleButton: View {
    @Environment(ListeningSessionHost.self) private var sessionHost

    var body: some View {
        Button("Shuffle", systemImage: "shuffle") {
            Task { await sessionHost.startFreshShuffle(autofillingEmptyDraft: true) }
        }
        .help("Start a fresh shuffle of your picks")
        .disabled(sessionHost.isStartingSession)
        .accessibilityIdentifier("mac.toolbar.shuffle")
    }
}
