import Foundation

actor ScrobbleManager {
    private let transports: [any ScrobbleTransport]

    init(transports: [any ScrobbleTransport]) {
        self.transports = transports
    }

    func scrobble(_ event: ScrobbleEvent) async {
        for transport in transports {
            guard await transport.isAuthenticated else { continue }
            await transport.scrobble(event)
        }
    }

    func sendNowPlaying(_ event: ScrobbleEvent) async {
        for transport in transports {
            guard await transport.isAuthenticated else { continue }
            await transport.sendNowPlaying(event)
        }
    }
}
