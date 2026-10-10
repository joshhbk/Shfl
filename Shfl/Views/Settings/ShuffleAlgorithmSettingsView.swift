import ShflComposition
import ShflCore
import SwiftUI

struct ShuffleAlgorithmSettingsView: View {
    @Environment(SessionDraftStore.self) private var sessionDraft
    @Environment(\.listeningSessionHost) private var sessionHost
    @Environment(\.shufflePlayer) private var player

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
                // The chosen algorithm is already staged on the draft.
                Task { await sessionHost?.startFreshShuffle() }
            } label: {
                if sessionHost?.isStartingSession == true {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Start New Shuffle Now")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(sessionHost?.isStartingSession ?? true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    private var algorithmGrid: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(ShuffleAlgorithm.allCases, id: \.self) { algorithm in
                AlgorithmCard(
                    algorithm: algorithm,
                    isSelected: sessionDraft.algorithm == algorithm,
                    action: {
                        guard sessionDraft.algorithm != algorithm else { return }
                        withAnimation(.easeInOut(duration: 0.2)) {
                            sessionDraft.stage(algorithm)
                        }
                    }
                )
            }
        }
    }

    private var descriptionSection: some View {
        Text(sessionDraft.algorithm.description)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
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
        content
            .glassEffect(
                isSelected ? .regular.interactive() : .regular,
                in: .rect(cornerRadius: cornerRadius)
            )
    }
}

#Preview {
    NavigationStack {
        ShuffleAlgorithmSettingsView()
    }
    .environment(AppModel.preview().sessionDraft)
}
