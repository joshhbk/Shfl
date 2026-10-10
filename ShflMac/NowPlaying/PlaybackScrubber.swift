import ShflCore
import SwiftUI

struct PlaybackScrubber: View {
    @State private var clock: PlaybackClock?
    @Environment(\.screenFactories) private var screens
    @Environment(ShufflePlayer.self) private var player

    var body: some View {
        Group {
            if let clock, player.playbackState.currentSong != nil {
                ScrubberTrack(clock: clock, onSeek: seek)
            } else {
                ScrubberTrackPlaceholder()
            }
        }
        .onAppear {
            if clock == nil { clock = screens.makePlaybackClock() }
            clock?.startUpdating(playbackState: player.playbackState)
        }
        .onDisappear { clock?.stopUpdating() }
        .onChange(of: player.playbackState) { _, state in
            clock?.handlePlaybackStateChange(state)
        }
    }

    private func seek(to time: TimeInterval) {
        player.seek(to: time)
        clock?.handleUserSeek(to: time)
    }
}

private struct ScrubberTrack: View {
    let clock: PlaybackClock
    let onSeek: (TimeInterval) -> Void

    @State private var isDragging = false
    @State private var draggedTime: TimeInterval?

    private var shownTime: TimeInterval { draggedTime ?? clock.currentTime }

    var body: some View {
        HStack(spacing: 8) {
            Text(PlaybackTimeFormat.string(for: shownTime))
                .accessibilityIdentifier("mac.scrubber.elapsed")
            Slider(
                value: Binding(get: { shownTime }, set: move(to:)),
                in: 0...max(clock.duration, 1),
                onEditingChanged: dragChanged
            )
            .controlSize(.small)
            .disabled(clock.duration <= 0)
            .accessibilityLabel("Playback position")
            .accessibilityIdentifier("mac.scrubber")
            Text(PlaybackTimeFormat.string(for: clock.duration))
                .accessibilityIdentifier("mac.scrubber.duration")
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
    }

    // VoiceOver and arrow-key changes arrive outside a drag, so they seek at once.
    private func move(to time: TimeInterval) {
        if isDragging {
            draggedTime = time
        } else {
            onSeek(time)
        }
    }

    private func dragChanged(_ isEditing: Bool) {
        isDragging = isEditing
        guard !isEditing, let draggedTime else { return }
        onSeek(draggedTime)
        self.draggedTime = nil
    }
}

private struct ScrubberTrackPlaceholder: View {
    var body: some View {
        Slider(value: .constant(0))
            .controlSize(.small)
            .disabled(true)
    }
}

enum PlaybackTimeFormat {
    static func string(for time: TimeInterval) -> String {
        let pattern: Duration.TimeFormatStyle.Pattern = time >= 3600 ? .hourMinuteSecond : .minuteSecond
        return Duration.seconds(max(0, time).rounded(.down)).formatted(.time(pattern: pattern))
    }
}
