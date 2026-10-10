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
    @Environment(ShufflePlayer.self) private var player

    var body: some View {
        Button("Previous", systemImage: "backward.fill") {
            Task { try? await player.restartOrSkipToPrevious() }
        }
        .font(.title3)
        .disabled(player.activeSession == nil)
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
    @Environment(ShufflePlayer.self) private var player

    var body: some View {
        Button("Next", systemImage: "forward.fill") {
            Task { try? await player.skipToNext() }
        }
        .font(.title3)
        .disabled(player.activeSession == nil)
        .accessibilityIdentifier("mac.transport.next")
    }
}
