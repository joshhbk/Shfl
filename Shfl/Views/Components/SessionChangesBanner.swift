import ShflCore
import SwiftUI

/// Tells the listener that picks made during a listening session wait for the
/// next shuffle, and offers to start that shuffle now. Shows only while the
/// draft differs from the playing session.
struct SessionChangesBanner: View {
    @Environment(\.listeningSessionHost) private var sessionHost
    @Environment(\.sessionDraft) private var sessionDraft
    @Environment(\.shuffleTheme) private var shuffleTheme

    var body: some View {
        if let sessionHost,
           sessionHost.player.activeSession != nil,
           sessionHost.player.hasPendingSessionChanges {
            HStack(spacing: 12) {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    Task { await sessionHost.startFreshShuffle(autofillingEmptyDraft: true) }
                } label: {
                    if sessionHost.isStartingSession {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label(buttonTitle, systemImage: "shuffle")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(shuffleTheme.interactionColor)
                .fixedSize()
                .disabled(sessionHost.isStartingSession)
                .accessibilityIdentifier("songPicker.startNewShuffle")
            }
            .padding(12)
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private var message: String {
        sessionDraft.isEmpty
            ? "Nothing picked. Playback stops after this shuffle."
            : "Your picks apply to the next shuffle."
    }

    private var buttonTitle: String {
        sessionDraft.isEmpty ? "Autofill" : "Shuffle Now"
    }
}
