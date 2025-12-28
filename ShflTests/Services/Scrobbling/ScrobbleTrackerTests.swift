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

    // MARK: - Playback Tracking Tests

    @Test("Scrobble fires when threshold reached")
    func scrobbleOnThreshold() async throws {
        let transport = MockScrobbleTransport()
        let manager = ScrobbleManager(transports: [transport])
        let mockService = MockMusicService()
        let tracker = await ScrobbleTracker(scrobbleManager: manager, musicService: mockService)

        let song = Song(
            id: "1",
            title: "Test Song",
            artist: "Test Artist",
            albumTitle: "Test Album",
            artworkURL: nil
        )

        // Simulate playing for threshold duration (song is 60 seconds, threshold is 30)
        mockService.mockDuration = 60
        await tracker.onPlaybackStateChanged(.playing(song))

        // Simulate time passing (threshold is 30 seconds for 60-second song)
        await tracker.simulateTimeElapsed(seconds: 31)

        // Allow async work to complete
        try await Task.sleep(for: .milliseconds(50))

        let scrobbled = await transport.scrobbledEvents
        #expect(scrobbled.count == 1)
        #expect(scrobbled.first?.track == "Test Song")
    }

    @Test("Now playing sent when playback starts")
    func nowPlayingOnStart() async throws {
        let transport = MockScrobbleTransport()
        let manager = ScrobbleManager(transports: [transport])
        let mockService = MockMusicService()
        let tracker = await ScrobbleTracker(scrobbleManager: manager, musicService: mockService)

        let song = Song(
            id: "1",
            title: "Test Song",
            artist: "Test Artist",
            albumTitle: "Test Album",
            artworkURL: nil
        )

        mockService.mockDuration = 180
        await tracker.onPlaybackStateChanged(.playing(song))

        // Allow async work to complete
        try await Task.sleep(for: .milliseconds(50))

        let nowPlaying = await transport.nowPlayingEvents
        #expect(nowPlaying.count == 1)
    }

    @Test("Pausing stops time accumulation")
    func pauseStopsTracking() async throws {
        let transport = MockScrobbleTransport()
        let manager = ScrobbleManager(transports: [transport])
        let mockService = MockMusicService()
        let tracker = await ScrobbleTracker(scrobbleManager: manager, musicService: mockService)

        let song = Song(
            id: "1",
            title: "Test Song",
            artist: "Test Artist",
            albumTitle: "Test Album",
            artworkURL: nil
        )

        mockService.mockDuration = 60
        await tracker.onPlaybackStateChanged(.playing(song))
        await tracker.simulateTimeElapsed(seconds: 20)
        await tracker.onPlaybackStateChanged(.paused(song))
        await tracker.simulateTimeElapsed(seconds: 20)  // This shouldn't count

        try await Task.sleep(for: .milliseconds(50))

        let scrobbled = await transport.scrobbledEvents
        #expect(scrobbled.count == 0)  // Didn't reach threshold
    }

    @Test("Scrobble fires only once per song")
    func scrobbleOnlyOnce() async throws {
        let transport = MockScrobbleTransport()
        let manager = ScrobbleManager(transports: [transport])
        let mockService = MockMusicService()
        let tracker = await ScrobbleTracker(scrobbleManager: manager, musicService: mockService)

        let song = Song(
            id: "1",
            title: "Test Song",
            artist: "Test Artist",
            albumTitle: "Test Album",
            artworkURL: nil
        )

        mockService.mockDuration = 60
        await tracker.onPlaybackStateChanged(.playing(song))
        await tracker.simulateTimeElapsed(seconds: 35)  // Past threshold
        try await Task.sleep(for: .milliseconds(50))

        await tracker.simulateTimeElapsed(seconds: 20)  // More time
        try await Task.sleep(for: .milliseconds(50))

        let scrobbled = await transport.scrobbledEvents
        #expect(scrobbled.count == 1)  // Still just one
    }

    @Test("Song change resets tracking")
    func songChangeResets() async throws {
        let transport = MockScrobbleTransport()
        let manager = ScrobbleManager(transports: [transport])
        let mockService = MockMusicService()
        let tracker = await ScrobbleTracker(scrobbleManager: manager, musicService: mockService)

        let song1 = Song(id: "1", title: "Song 1", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        let song2 = Song(id: "2", title: "Song 2", artist: "Artist", albumTitle: "Album", artworkURL: nil)

        mockService.mockDuration = 60
        await tracker.onPlaybackStateChanged(.playing(song1))
        await tracker.simulateTimeElapsed(seconds: 20)

        // Change song before threshold
        await tracker.onPlaybackStateChanged(.playing(song2))
        await tracker.simulateTimeElapsed(seconds: 35)

        try await Task.sleep(for: .milliseconds(50))

        let scrobbled = await transport.scrobbledEvents
        #expect(scrobbled.count == 1)
        #expect(scrobbled.first?.track == "Song 2")
    }
}
