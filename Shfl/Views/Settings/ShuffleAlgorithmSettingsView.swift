import SwiftUI

struct ShuffleAlgorithmSettingsView: View {
    @Environment(\.appSettings) private var appSettings

    var body: some View {
        Form {
            Section {
                ForEach(ShuffleAlgorithm.allCases, id: \.self) { algo in
                    Button {
                        appSettings?.shuffleAlgorithm = algo
                    } label: {
                        HStack {
                            Text(algo.displayName)
                                .foregroundStyle(.primary)
                            Spacer()
                            if appSettings?.shuffleAlgorithm == algo {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }
            } footer: {
                if let algorithm = appSettings?.shuffleAlgorithm {
                    Text(algorithm.description)
                }
            }
        }
        .navigationTitle("Shuffle Algorithm")
    }
}

#Preview {
    NavigationStack {
        ShuffleAlgorithmSettingsView()
    }
    .environment(\.appSettings, AppSettings())
}
