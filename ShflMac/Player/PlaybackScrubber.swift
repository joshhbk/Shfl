import ShflCore
import ShflDesign
import SwiftUI

/// The player's position track and times. Owns the playback clock for as long as it's on screen.
struct PlaybackScrubber: View {
    @State private var clock: PlaybackClock?
    @Environment(\.screenFactories) private var screens
    @Environment(ShufflePlayer.self) private var player
    @Environment(ListeningSessionHost.self) private var sessionHost

    var body: some View {
        Group {
            if let clock, player.playbackState.currentSong != nil {
                LiveScrubber(clock: clock, onSeek: seek)
            } else {
                IdleScrubber(isFilled: false)
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
        sessionHost.seek(to: time)
        clock?.handleUserSeek(to: time)
    }
}

/// A track with nothing to scrub: empty before anything plays, full once a session has finished.
struct IdleScrubber: View {
    let isFilled: Bool

    var body: some View {
        VStack(spacing: Spacing.s8) {
            Scrubber(value: .constant(isFilled ? 1 : 0), in: 0...1, step: 1)
                .disabled(true)
                .accessibilityLabel("Playback position")
            if !isFilled {
                PlaybackTimes(elapsed: 0, remaining: 0)
            }
        }
    }
}

private struct LiveScrubber: View {
    let clock: PlaybackClock
    let onSeek: (TimeInterval) -> Void

    @State private var draggedTime: TimeInterval?

    private var shownTime: TimeInterval { draggedTime ?? clock.currentTime }

    var body: some View {
        VStack(spacing: Spacing.s8) {
            Scrubber(
                value: Binding(get: { shownTime }, set: { draggedTime = $0 }),
                in: 0...max(clock.duration, 1),
                step: 5,
                onEditingChanged: commit
            )
            .disabled(clock.duration <= 0)
            .accessibilityLabel("Playback position")
            .accessibilityValue(
                "\(PlaybackTimeFormat.spoken(for: shownTime)) of \(PlaybackTimeFormat.spoken(for: clock.duration))"
            )
            .accessibilityIdentifier("mac.scrubber")
            PlaybackTimes(elapsed: shownTime, remaining: clock.duration - shownTime)
        }
    }

    private func commit(_ isEditing: Bool) {
        guard !isEditing, let draggedTime else { return }
        onSeek(draggedTime)
        self.draggedTime = nil
    }
}

private struct PlaybackTimes: View {
    let elapsed: TimeInterval
    let remaining: TimeInterval

    var body: some View {
        HStack {
            Text(PlaybackTimeFormat.string(for: elapsed))
                .accessibilityIdentifier("mac.scrubber.elapsed")
            Spacer()
            Text("\u{2212}\(PlaybackTimeFormat.string(for: remaining))")
                .accessibilityIdentifier("mac.scrubber.remaining")
        }
        .font(.secondaryText.monospacedDigit())
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }
}

enum PlaybackTimeFormat {
    static func string(for time: TimeInterval) -> String {
        let pattern: Duration.TimeFormatStyle.Pattern = time >= 3600 ? .hourMinuteSecond : .minuteSecond
        return Duration.seconds(max(0, time).rounded(.down)).formatted(.time(pattern: pattern))
    }

    static func spoken(for time: TimeInterval) -> String {
        Duration.seconds(max(0, time).rounded(.down)).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))
    }
}
