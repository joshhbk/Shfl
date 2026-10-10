import Foundation
import Testing
@testable import Shfl

@Suite("PlaybackClock Tests")
@MainActor
struct PlaybackClockTests {
    private let song = Song(
        id: "song-1",
        title: "Test Song",
        artist: "Test Artist",
        albumTitle: "Test Album",
        artworkURL: nil
    )

    @Test("Polling mode resolver disables updates when playback is not playing")
    func resolvePollingModeDisablesWhenNotPlaying() {
        let now = Date()
        let boostUntil = now.addingTimeInterval(5)

        #expect(
            PlaybackClock.resolvePollingMode(
                isTrackingEnabled: true,
                playbackState: .paused(song),
                now: now,
                boostUntil: boostUntil
            ) == .disabled
        )
        #expect(
            PlaybackClock.resolvePollingMode(
                isTrackingEnabled: true,
                playbackState: .stopped,
                now: now,
                boostUntil: boostUntil
            ) == .disabled
        )
        #expect(
            PlaybackClock.resolvePollingMode(
                isTrackingEnabled: false,
                playbackState: .playing(song),
                now: now,
                boostUntil: boostUntil
            ) == .disabled
        )
    }

    @Test("Transitions from boosted polling to steady polling after boost window")
    func transitionsBoostedToSteady() async {
        let musicService = DeterministicMusicService()
        let state = PlaybackClock(
            playbackTransport: musicService,
            boostedUpdateInterval: 0.05,
            steadyUpdateInterval: 0.25,
            boostDuration: 0.08
        )
        defer { state.stopUpdating() }

        state.startUpdating(playbackState: .playing(song))

        #expect(state.pollingMode == .boosted)
        #expect(hasApproxValue(state.activeUpdateInterval, expected: 0.05))

        try? await Task.sleep(nanoseconds: 220_000_000)

        #expect(state.pollingMode == .steady)
        #expect(hasApproxValue(state.activeUpdateInterval, expected: 0.25))
    }

    @Test("Pausing disables polling and user seek re-enables boost while playing")
    func seekAndPauseTransitions() async {
        let musicService = DeterministicMusicService()
        await musicService.setPlaybackDuration(240)
        let state = PlaybackClock(
            playbackTransport: musicService,
            boostedUpdateInterval: 0.05,
            steadyUpdateInterval: 0.2,
            boostDuration: 0.06
        )
        defer { state.stopUpdating() }

        state.startUpdating(playbackState: .playing(song))
        try? await Task.sleep(nanoseconds: 200_000_000)
        #expect(state.pollingMode == .steady)

        state.handlePlaybackStateChange(.paused(song))
        #expect(state.pollingMode == .disabled)
        #expect(state.activeUpdateInterval == nil)

        state.handlePlaybackStateChange(.playing(song))
        try? await Task.sleep(nanoseconds: 20_000_000)
        #expect(state.pollingMode == .boosted)

        state.handleUserSeek(to: 120)
        #expect(state.currentTime == 120)
        #expect(state.pollingMode == .boosted)
    }

    private func hasApproxValue(_ value: TimeInterval?, expected: TimeInterval) -> Bool {
        guard let value else { return false }
        return abs(value - expected) < 0.01
    }
}
