import ShflCore
import SwiftUI

struct LibraryToolbar: ToolbarContent {
    var body: some ToolbarContent {
        ToolbarItem { AutofillButton() }
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
