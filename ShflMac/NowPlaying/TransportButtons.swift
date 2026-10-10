import ShflCore
import SwiftUI

struct TransportButtons: View {
    var body: some View {
        HStack(spacing: 14) {
            PreviousButton()
            PlayPauseButton()
            NextButton()
        }
        .buttonStyle(.borderless)
        .labelStyle(.iconOnly)
    }
}

private struct PreviousButton: View {
    @Environment(ListeningSessionHost.self) private var sessionHost

    var body: some View {
        Button("Previous", systemImage: "backward.fill") {
            Task { await sessionHost.skipToPrevious() }
        }
        .font(.title3)
        .disabled(!sessionHost.canSkip)
        .accessibilityIdentifier("mac.transport.previous")
    }
}

private struct PlayPauseButton: View {
    @Environment(ShufflePlayer.self) private var player
    @Environment(ListeningSessionHost.self) private var sessionHost

    var body: some View {
        let isPlaying = player.playbackState.isPlaying
        Button(isPlaying ? "Pause" : "Play", systemImage: isPlaying ? "pause.fill" : "play.fill") {
            Task { await sessionHost.togglePlayback() }
        }
        .font(.title)
        .contentTransition(.symbolEffect(.replace))
        .disabled(sessionHost.isStartingSession)
        .accessibilityIdentifier("mac.transport.playPause")
    }
}

private struct NextButton: View {
    @Environment(ListeningSessionHost.self) private var sessionHost

    var body: some View {
        Button("Next", systemImage: "forward.fill") {
            Task { await sessionHost.skipToNext() }
        }
        .font(.title3)
        .disabled(!sessionHost.canSkip)
        .accessibilityIdentifier("mac.transport.next")
    }
}
