import SwiftUI

struct AutofillSettingsView: View {
    @AppStorage("autofillAlgorithm") private var algorithmRaw: String = AutofillAlgorithm.random.rawValue

    private var algorithm: AutofillAlgorithm {
        AutofillAlgorithm(rawValue: algorithmRaw) ?? .random
    }

    var body: some View {
        Form {
            Section {
                ForEach(Array(AutofillAlgorithm.allCases), id: \.self) { algo in
                    Button {
                        algorithmRaw = algo.rawValue
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
}
