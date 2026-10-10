import Foundation

package nonisolated struct ScrobbleEvent: Sendable, Equatable, Codable {
    package let track: String
    package let artist: String
    package let album: String
    package let timestamp: Date
    package let durationSeconds: Int
}
