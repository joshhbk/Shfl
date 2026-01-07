import Foundation

struct ScrobbleEvent: Sendable, Equatable, Codable {
    let track: String
    let artist: String
    let album: String
    let timestamp: Date
    let durationSeconds: Int
}
