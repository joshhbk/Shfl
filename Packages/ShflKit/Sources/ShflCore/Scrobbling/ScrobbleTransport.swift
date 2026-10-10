import Foundation

package nonisolated protocol ScrobbleTransport: Sendable {
    var isAuthenticated: Bool { get async }
    func scrobble(_ event: ScrobbleEvent) async
    func sendNowPlaying(_ event: ScrobbleEvent) async
}
