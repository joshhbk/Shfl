import SwiftUI

struct AutofillSettingsView: View {
    @Environment(\.libraryPreferences) private var libraryPreferences

    private var algorithm: AutofillAlgorithm {
        libraryPreferences?.autofillAlgorithm ?? .random
    }

    var body: some View {
        Form {
            Section {
                ForEach(Array(AutofillAlgorithm.allCases), id: \.self) { algo in
                    Button {
                        libraryPreferences?.autofillAlgorithm = algo
                    } label: {
                        HStack {
                            Text(algo.displayName)
                                .foregroundStyle(.primary)
                            Spacer()
                            if algorithm == algo {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }
            } footer: {
                Text(algorithmDescription)
            }
        }
        .navigationTitle("Autofill")
    }

    private var algorithmDescription: String {
        switch algorithm {
        case .random:
            return "Fills with random songs from your library."
        case .recentlyAdded:
            return "Fills with your most recently added songs."
        }
    }
}

#Preview {
    NavigationStack {
        AutofillSettingsView()
    }
    .environment(\.libraryPreferences, LibraryPreferences())
}
