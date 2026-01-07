import Foundation
import Testing
@testable import Shfl

@Suite("ScrobbleManager Tests")
struct ScrobbleManagerTests {

    @Test("Manager broadcasts scrobble to all transports")
    func broadcastsScrobble() async {
        let transport1 = MockScrobbleTransport()
        let transport2 = MockScrobbleTransport()
        let manager = ScrobbleManager(transports: [transport1, transport2])

        let event = ScrobbleEvent(
            track: "Test",
            artist: "Artist",
            album: "Album",
            timestamp: Date(),
            durationSeconds: 180
        )

        await manager.scrobble(event)

        let events1 = await transport1.scrobbledEvents
        let events2 = await transport2.scrobbledEvents
        #expect(events1.count == 1)
        #expect(events2.count == 1)
    }

    @Test("Manager broadcasts now playing to all transports")
    func broadcastsNowPlaying() async {
        let transport1 = MockScrobbleTransport()
        let transport2 = MockScrobbleTransport()
        let manager = ScrobbleManager(transports: [transport1, transport2])

        let event = ScrobbleEvent(
            track: "Test",
            artist: "Artist",
            album: "Album",
            timestamp: Date(),
            durationSeconds: 180
        )

        await manager.sendNowPlaying(event)

        let events1 = await transport1.nowPlayingEvents
        let events2 = await transport2.nowPlayingEvents
        #expect(events1.count == 1)
        #expect(events2.count == 1)
    }

    @Test("Manager only scrobbles to authenticated transports")
    func onlyAuthenticatedTransports() async {
        let authenticated = MockScrobbleTransport()
        let unauthenticated = MockScrobbleTransport()
        await unauthenticated.setAuthenticated(false)

        let manager = ScrobbleManager(transports: [authenticated, unauthenticated])

        let event = ScrobbleEvent(
            track: "Test",
            artist: "Artist",
            album: "Album",
            timestamp: Date(),
            durationSeconds: 180
        )

        await manager.scrobble(event)

        let authEvents = await authenticated.scrobbledEvents
        let unauthEvents = await unauthenticated.scrobbledEvents
        #expect(authEvents.count == 1)
        #expect(unauthEvents.count == 0)
    }
}
