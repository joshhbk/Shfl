import SwiftUI

extension Notification.Name {
    static let shuffleAlgorithmChanged = Notification.Name("shuffleAlgorithmChanged")
}

struct ShuffleAlgorithmSettingsView: View {
    @AppStorage("shuffleAlgorithm") private var algorithmRaw: String = ShuffleAlgorithm.noRepeat.rawValue

    private var algorithm: ShuffleAlgorithm {
        ShuffleAlgorithm(rawValue: algorithmRaw) ?? .noRepeat
    }

    var body: some View {
        Form {
            Section {
                ForEach(ShuffleAlgorithm.allCases, id: \.self) { algo in
                    Button {
                        guard algorithmRaw != algo.rawValue else { return }
                        algorithmRaw = algo.rawValue
                        NotificationCenter.default.post(name: .shuffleAlgorithmChanged, object: nil)
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
                Text(algorithm.description)
            }
        }
        .navigationTitle("Shuffle Algorithm")
    }
}

#Preview {
    NavigationStack {
        ShuffleAlgorithmSettingsView()
    }
}
