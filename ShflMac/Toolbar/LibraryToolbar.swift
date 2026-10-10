import ShflCore
import SwiftUI

struct LibraryToolbar: ToolbarContent {
    var body: some ToolbarContent {
        ToolbarItem { SortMenu() }
        ToolbarItem { AutofillButton() }
        ToolbarItem { ShuffleButton() }
    }
}

private struct SortMenu: View {
    @Environment(LibraryBrowser.self) private var browser

    var body: some View {
        Menu {
            SongSortPicker(selection: browser.sortSelection)
                .pickerStyle(.inline)
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
        .help("Sort Songs")
        .accessibilityIdentifier("mac.toolbar.sort")
    }
}

private struct AutofillButton: View {
    @Environment(DraftEditing.self) private var drafting

    var body: some View {
        Button("Autofill", systemImage: "wand.and.stars") {
            Task { await drafting.autofill() }
        }
        .help("Fill Selected with songs from your library")
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
        .help("Start a fresh shuffle of Selected")
        .disabled(sessionHost.isStartingSession)
        .accessibilityIdentifier("mac.toolbar.shuffle")
    }
}
