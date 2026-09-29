import Foundation
import Testing
@testable import Shfl

actor MockScrobbleTransport {
    private var _isAuthenticated: Bool = true
    var isAuthenticated: Bool { _isAuthenticated }
    private(set) var scrobbledEvents: [ScrobbleEvent] = []
    private(set) var nowPlayingEvents: [ScrobbleEvent] = []

    func setAuthenticated(_ value: Bool) {
        _isAuthenticated = value
    }

    func scrobble(_ event: ScrobbleEvent) async {
        scrobbledEvents.append(event)
    }

    func sendNowPlaying(_ event: ScrobbleEvent) async {
        nowPlayingEvents.append(event)
    }
}

// Declared in an extension: Xcode 27 infers `nonisolated` onto an actor that
// lists a nonisolated protocol on its primary declaration, then rejects it.
extension MockScrobbleTransport: ScrobbleTransport {}

@Suite("ScrobbleTransport Tests")
struct ScrobbleTransportTests {

    @Test("Transport receives scrobble events")
    func scrobbleEvent() async {
        let transport = MockScrobbleTransport()
        let event = ScrobbleEvent(
            track: "Test",
            artist: "Artist",
            album: "Album",
            timestamp: Date(),
            durationSeconds: 180
        )

        await transport.scrobble(event)

        let events = await transport.scrobbledEvents
        #expect(events.count == 1)
        #expect(events.first == event)
    }

    @Test("Transport receives now playing events")
    func nowPlayingEvent() async {
        let transport = MockScrobbleTransport()
        let event = ScrobbleEvent(
            track: "Test",
            artist: "Artist",
            album: "Album",
            timestamp: Date(),
            durationSeconds: 180
        )

        await transport.sendNowPlaying(event)

        let events = await transport.nowPlayingEvents
        #expect(events.count == 1)
    }
}
