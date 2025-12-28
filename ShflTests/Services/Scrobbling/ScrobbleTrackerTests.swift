import Testing
@testable import Shfl

@Suite("ScrobbleTracker Tests")
struct ScrobbleTrackerTests {

    // MARK: - Threshold Calculation Tests

    @Test("Threshold is half duration for short songs")
    func thresholdHalfDuration() {
        // 2 minute song = 120 seconds, threshold should be 60 seconds
        let threshold = ScrobbleTracker.scrobbleThreshold(forDurationSeconds: 120)
        #expect(threshold == 60)
    }

    @Test("Threshold is 4 minutes for long songs")
    func thresholdFourMinutes() {
        // 10 minute song = 600 seconds, threshold should be 240 seconds (4 min)
        let threshold = ScrobbleTracker.scrobbleThreshold(forDurationSeconds: 600)
        #expect(threshold == 240)
    }

    @Test("Threshold is half for songs under 8 minutes")
    func thresholdBoundary() {
        // 8 minute song = 480 seconds, half = 240, so threshold is 240
        let threshold = ScrobbleTracker.scrobbleThreshold(forDurationSeconds: 480)
        #expect(threshold == 240)
    }

    @Test("Songs under 30 seconds should not scrobble")
    func shortSongsNoScrobble() {
        let shouldScrobble = ScrobbleTracker.shouldScrobble(durationSeconds: 25)
        #expect(shouldScrobble == false)
    }

    @Test("Songs 30 seconds or more should scrobble")
    func normalSongsScrobble() {
        let shouldScrobble = ScrobbleTracker.shouldScrobble(durationSeconds: 30)
        #expect(shouldScrobble == true)
    }
}
