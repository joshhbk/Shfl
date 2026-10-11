import ShflCore
import ShflDesign
import SwiftUI

/// The click wheel wired to the session host. Every label comes from the host's intents.
struct TransportWheel: View {
    @Binding var isShowingSession: Bool

    @Environment(ListeningSessionHost.self) private var sessionHost

    var body: some View {
        let intents = sessionHost.intents
        ClickWheel(onKeyboardPress: press) {
            Button(intents.play.title, systemImage: intents.play.systemImage, action: playOrPause)
                .contentTransition(.symbolEffect(.replace))
                .accessibilityHint(intents.play.accessibilityHint ?? "")
                .disabled(!isEnabled(.center))
                .accessibilityIdentifier("mac.transport.playPause")
        } top: {
            Button(intents.shuffle.title, systemImage: "shuffle", action: shuffle)
                .disabled(!isEnabled(.top))
                .accessibilityIdentifier("mac.transport.shuffle")
        } leading: {
            Button("Previous", systemImage: "backward.fill", action: previous)
                .disabled(!isEnabled(.leading))
                .accessibilityIdentifier("mac.transport.previous")
        } trailing: {
            Button("Next", systemImage: "forward.fill", action: next)
                .disabled(!isEnabled(.trailing))
                .accessibilityIdentifier("mac.transport.next")
        } bottom: {
            Toggle(
                isShowingSession ? "Show Artwork" : "Show the Whole Session",
                systemImage: "list.bullet",
                isOn: $isShowingSession
            )
            .disabled(!isEnabled(.bottom))
            .accessibilityIdentifier("mac.transport.session")
        }
        .accessibilityLabel("Playback controls")
    }

    private func isEnabled(_ slot: ClickWheelSlot) -> Bool {
        switch slot {
        case .center, .top: !sessionHost.isStartingSession
        case .leading, .trailing: sessionHost.canSkip
        case .bottom: sessionHost.timeline.status != .idle
        }
    }

    private func press(_ slot: ClickWheelSlot) {
        guard isEnabled(slot) else { return }
        switch slot {
        case .center: playOrPause()
        case .top: shuffle()
        case .leading: previous()
        case .trailing: next()
        case .bottom: isShowingSession.toggle()
        }
    }

    private func playOrPause() {
        Task { await sessionHost.togglePlayback() }
    }

    private func shuffle() {
        Task { await sessionHost.startFreshShuffle(autofillingEmptyDraft: true) }
    }

    private func previous() {
        Task { await sessionHost.skipToPrevious() }
    }

    private func next() {
        Task { await sessionHost.skipToNext() }
    }
}
