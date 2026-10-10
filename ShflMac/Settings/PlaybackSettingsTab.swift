import ShflCore
import SwiftUI

// Form rows get bindings, not environment objects: rows AppKit builds for accessibility lack the environment.
struct PlaybackSettingsTab: View {
    @Environment(DraftEditing.self) private var drafting
    @Environment(LibraryPreferences.self) private var preferences

    var body: some View {
        @Bindable var preferences = preferences
        let draft = drafting.draft
        Form {
            ShuffleAlgorithmPicker(selection: Binding(get: { draft.algorithm }, set: draft.stage))
            AutofillAlgorithmPicker(selection: $preferences.autofillAlgorithm)
        }
        .formStyle(.grouped)
    }
}

private struct ShuffleAlgorithmPicker: View {
    let selection: Binding<ShuffleAlgorithm>

    var body: some View {
        Section {
            Picker("Shuffle", selection: selection) {
                ForEach(ShuffleAlgorithm.allCases, id: \.self) { algorithm in
                    Text(algorithm.displayName).tag(algorithm)
                }
            }
            .pickerStyle(.radioGroup)
            .accessibilityIdentifier("mac.settings.shuffleAlgorithm")
        } footer: {
            Text(selection.wrappedValue.description)
                .foregroundStyle(.secondary)
        }
    }
}

private struct AutofillAlgorithmPicker: View {
    let selection: Binding<AutofillAlgorithm>

    var body: some View {
        Section {
            Picker("Autofill picks", selection: selection) {
                ForEach(AutofillAlgorithm.allCases, id: \.self) { algorithm in
                    Text(algorithm.displayName).tag(algorithm)
                }
            }
            .pickerStyle(.radioGroup)
            .accessibilityIdentifier("mac.settings.autofillAlgorithm")
        } footer: {
            Text("How Autofill chooses songs from your library.")
                .foregroundStyle(.secondary)
        }
    }
}
