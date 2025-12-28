import SwiftUI

struct AutofillSettingsView: View {
    @AppStorage("autofillAlgorithm") private var algorithmRaw: String = AutofillAlgorithm.random.rawValue

    private var algorithm: AutofillAlgorithm {
        AutofillAlgorithm(rawValue: algorithmRaw) ?? .random
    }

    var body: some View {
        Form {
            Section {
                Picker("Algorithm", selection: $algorithmRaw) {
                    ForEach(AutofillAlgorithm.allCases, id: \.rawValue) { algo in
                        Text(algo.displayName).tag(algo.rawValue)
                    }
                }
                .pickerStyle(.segmented)
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
}
