import ShflCore
import SwiftUI

struct PicksCommands: Commands {
    let drafting: DraftEditing

    @FocusedValue(\.songSelection) private var selection

    var body: some Commands {
        CommandMenu("Picks") {
            Button("Add to Picks") {
                drafting.add(selection?.songs ?? [])
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(selection?.songs.isEmpty ?? true)

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
