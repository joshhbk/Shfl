import SwiftUI

struct ShuffleAlgorithmSettingsView: View {
    @Environment(\.appSettings) private var appSettings
    @Environment(\.shufflePlayer) private var player
    @State private var isStartingNewShuffle = false

    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                algorithmGrid
                descriptionSection
                if player?.activeSession != nil {
                    nextShuffleSection
                }
            }
            .padding()
        }
        .navigationTitle("Shuffle Algorithm")
    }

    private var nextShuffleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Applies to the next shuffle", systemImage: "forward.end")
                .font(.subheadline.weight(.semibold))
            Text("The songs already playing keep their current order. Start a new shuffle now if you want to apply this setting immediately.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button {
                guard let player else { return }
                isStartingNewShuffle = true
                Task {
                    try? await player.startFreshShuffle(
                        algorithm: appSettings?.shuffleAlgorithm
                    )
                    isStartingNewShuffle = false
                }
            } label: {
                if isStartingNewShuffle {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Start New Shuffle Now")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isStartingNewShuffle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    private var algorithmGrid: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(ShuffleAlgorithm.allCases, id: \.self) { algorithm in
                AlgorithmCard(
                    algorithm: algorithm,
                    isSelected: appSettings?.shuffleAlgorithm == algorithm,
                    action: {
                        guard appSettings?.shuffleAlgorithm != algorithm else { return }
                        withAnimation(.easeInOut(duration: 0.2)) {
                            appSettings?.shuffleAlgorithm = algorithm
                        }
                    }
                )
            }
        }
    }

    @ViewBuilder
    private var descriptionSection: some View {
        if let algorithm = appSettings?.shuffleAlgorithm {
            Text(algorithm.description)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
        }
    }
}

// MARK: - Algorithm Card

private struct AlgorithmCard: View {
    let algorithm: ShuffleAlgorithm
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: algorithm.iconName)
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .frame(width: 56, height: 56)

                HStack(spacing: 6) {
                    Text(algorithm.displayName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.accentColor)
                            .font(.subheadline)
                    }
                }
            }
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .modifier(SelectionCardGlassStyle(isSelected: isSelected, cornerRadius: 16))
        .accessibilityLabel("\(algorithm.displayName) shuffle algorithm")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Selection Card Glass Style

private struct SelectionCardGlassStyle: ViewModifier {
    let isSelected: Bool
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if #available(iOS 26, macOS 26, *) {
            glassContent(content)
        } else {
            fallbackContent(content)
        }
    }

    @available(iOS 26, macOS 26, *)
    @ViewBuilder
    private func glassContent(_ content: Content) -> some View {
        content
            .glassEffect(
                isSelected ? .regular.interactive() : .regular,
                in: .rect(cornerRadius: cornerRadius)
            )
    }

    @ViewBuilder
    private func fallbackContent(_ content: Content) -> some View {
        content
            .background(.background, in: .rect(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        isSelected ? Color.accentColor : Color.secondary.opacity(0.2),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
    }
}

#Preview {
    NavigationStack {
        ShuffleAlgorithmSettingsView()
    }
    .environment(\.appSettings, AppSettings())
}
