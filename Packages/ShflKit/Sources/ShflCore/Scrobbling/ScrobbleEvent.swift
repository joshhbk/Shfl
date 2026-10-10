import Foundation

// PR 4 → package
public nonisolated struct ScrobbleEvent: Sendable, Equatable, Codable {
    public let track: String
    public let artist: String
    public let album: String
    public let timestamp: Date
    public let durationSeconds: Int
}
