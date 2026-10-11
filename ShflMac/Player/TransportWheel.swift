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
                .disabled(sessionHost.isStartingSession)
                .accessibilityIdentifier("mac.transport.playPause")
        } top: {
            Button(intents.shuffle.title, systemImage: "shuffle", action: shuffle)
                .disabled(sessionHost.isStartingSession)
                .accessibilityIdentifier("mac.transport.shuffle")
        } leading: {
            Button("Previous", systemImage: "backward.fill", action: previous)
                .disabled(!sessionHost.canSkip)
                .accessibilityIdentifier("mac.transport.previous")
        } trailing: {
            Button("Next", systemImage: "forward.fill", action: next)
                .disabled(!sessionHost.canSkip)
                .accessibilityIdentifier("mac.transport.next")
        } bottom: {
            Toggle(
                isShowingSession ? "Show Artwork" : "Show the Whole Session",
                systemImage: "list.bullet",
                isOn: $isShowingSession
            )
            .disabled(sessionHost.timeline.status == .idle)
            .accessibilityIdentifier("mac.transport.session")
        }
        .accessibilityLabel("Playback controls")
    }

    private func press(_ slot: ClickWheelSlot) {
        switch slot {
        case .center:
            guard !sessionHost.isStartingSession else { return }
            playOrPause()
        case .top:
            guard !sessionHost.isStartingSession else { return }
            shuffle()
        case .leading:
            guard sessionHost.canSkip else { return }
            previous()
        case .trailing:
            guard sessionHost.canSkip else { return }
            next()
        case .bottom:
            guard sessionHost.timeline.status != .idle else { return }
            isShowingSession.toggle()
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
