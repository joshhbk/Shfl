import SwiftUI

struct AutofillSettingsView: View {
    @Environment(\.appSettings) private var appSettings

    private var algorithm: AutofillAlgorithm {
        appSettings?.autofillAlgorithm ?? .random
    }

    var body: some View {
        Form {
            Section {
                ForEach(Array(AutofillAlgorithm.allCases), id: \.self) { algo in
                    Button {
                        appSettings?.autofillAlgorithm = algo
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
    .environment(\.appSettings, AppSettings())
}
