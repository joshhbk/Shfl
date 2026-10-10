import ShflCore
import SwiftUI

struct SongsCommands: Commands {
    let drafting: DraftEditing

    @FocusedValue(\.songSelection) private var selection

    var body: some Commands {
        CommandMenu("Songs") {
            Button("Add Selection") {
                drafting.add(selection?.songs ?? [])
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(selection?.songs.isEmpty ?? true)

            Button("Autofill") {
                Task { await drafting.autofill() }
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])
            .disabled(drafting.draft.isAtCapacity)

            Button("Clear Selected") {
                drafting.clearAll()
            }
            .keyboardShortcut(.delete, modifiers: [.command, .shift])
            .disabled(drafting.draft.isEmpty)
        }
    }
}
