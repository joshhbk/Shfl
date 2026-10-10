import Foundation
@testable import ShflCore

// A copy of the mock in ShflCoreTests' ScrobbleTransportTests, kept for
// ScrobbleTrackerTests, which needs DeterministicMusicService and so stays in
// the app's tests. Delete it when those tests move into the package.
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
