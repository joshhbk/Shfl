import ShflCore
import SwiftUI

struct PlaybackSettingsTab: View {
    var body: some View {
        Form {
            ShuffleAlgorithmPicker()
            AutofillAlgorithmPicker()
        }
        .formStyle(.grouped)
    }
}

private struct ShuffleAlgorithmPicker: View {
    @Environment(DraftEditing.self) private var drafting

    var body: some View {
        let draft = drafting.draft
        Section {
            Picker("Shuffle", selection: Binding(get: { draft.algorithm }, set: draft.stage)) {
                ForEach(ShuffleAlgorithm.allCases, id: \.self) { algorithm in
                    Text(algorithm.displayName).tag(algorithm)
                }
            }
            .pickerStyle(.radioGroup)
            .accessibilityIdentifier("mac.settings.shuffleAlgorithm")
        } footer: {
            Text(draft.algorithm.description)
                .foregroundStyle(.secondary)
        }
    }
}

private struct AutofillAlgorithmPicker: View {
    @Environment(LibraryPreferences.self) private var preferences

    var body: some View {
        @Bindable var preferences = preferences
        Section {
            Picker("Autofill picks", selection: $preferences.autofillAlgorithm) {
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
