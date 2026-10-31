import ShflCore
import SwiftUI

/// Where Autofill takes songs from, as a checked list.
struct AutofillSourceItems: View {
    @Bindable var preferences: LibraryPreferences

    var body: some View {
        Picker("Autofill Using", selection: $preferences.autofillAlgorithm) {
            ForEach(AutofillAlgorithm.allCases, id: \.self) { algorithm in
                Text(algorithm.displayName).tag(algorithm)
            }
        }
        .pickerStyle(.inline)
        .labelsHidden()
    }
}
