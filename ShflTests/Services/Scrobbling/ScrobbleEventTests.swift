import Foundation
import Testing
@testable import Shfl

@Suite("ScrobbleEvent Tests")
struct ScrobbleEventTests {

    @Test("ScrobbleEvent initializes with all properties")
    func initialization() {
        let timestamp = Date()
        let event = ScrobbleEvent(
            track: "Never Gonna Give You Up",
            artist: "Rick Astley",
            album: "Whenever You Need Somebody",
            timestamp: timestamp,
            durationSeconds: 213
        )

        #expect(event.track == "Never Gonna Give You Up")
        #expect(event.artist == "Rick Astley")
        #expect(event.album == "Whenever You Need Somebody")
        #expect(event.timestamp == timestamp)
        #expect(event.durationSeconds == 213)
    }

    @Test("ScrobbleEvent is Sendable")
    func sendableConformance() async {
        let event = ScrobbleEvent(
            track: "Test",
            artist: "Artist",
            album: "Album",
            timestamp: Date(),
            durationSeconds: 180
        )

        // If this compiles, Sendable conformance works
        await Task { _ = event }.value
    }
}
