import ShflCore
import SwiftUI

/// ↩ and ⌫ belong to the focused list, not these items: as key equivalents they'd take keys from search and the wheel.
struct PicksCommands: Commands {
    let drafting: DraftEditing

    @FocusedValue(\.songSelection) private var selection

    var body: some Commands {
        CommandMenu("Picks") {
            PickMenuItems(selection: selection, drafting: drafting)

            Divider()

            Button("Autofill") {
                Task { await drafting.autofill() }
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])
            .disabled(!drafting.canAutofill)

            Button("Clear Picks") {
                drafting.clearAll()
            }
            .keyboardShortcut(.delete, modifiers: [.command, .shift])
            .disabled(drafting.draft.isEmpty)
        }
    }
}
