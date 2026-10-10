import Foundation
@testable import ShflCore

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

// In an extension: on the actor itself Xcode 27 infers nonisolated and rejects it.
extension MockScrobbleTransport: ScrobbleTransport {}
