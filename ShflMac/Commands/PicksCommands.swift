import ShflCore
import SwiftUI

/// ↩ and ⌫ belong to the focused list, not these items: as key equivalents they'd take keys from search and the wheel.
struct PicksCommands: Commands {
    let drafting: DraftEditing
    let preferences: LibraryPreferences

    @FocusedValue(\.songSelection) private var selection
    @FocusedValue(\.picksLayout) private var layout

    var body: some Commands {
        CommandMenu("Picks") {
            PickMenuItems(selection: selection, drafting: drafting)

            Divider()

            Button("Autofill") {
                Task { await drafting.autofill() }
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])
            .disabled(!drafting.canAutofill)

            Menu("Autofill Using") {
                AutofillSourceItems(preferences: preferences)
            }

            Button("Clear Picks") {
                drafting.clearAll()
            }
            .keyboardShortcut(.delete, modifiers: [.command, .shift])
            .disabled(drafting.draft.isEmpty)

            Divider()

            Menu("Shuffle Style") {
                ShuffleStyleItems(draft: drafting.draft)
            }
        }

        CommandGroup(after: .sidebar) {
            if let layout {
                Picker("Show Picks As", selection: layout) {
                    Text("Picks as Tray").tag(PicksLayout.tray)
                    Text("Picks as List").tag(PicksLayout.list)
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
        }
    }
}

private struct ShuffleStyleItems: View {
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
