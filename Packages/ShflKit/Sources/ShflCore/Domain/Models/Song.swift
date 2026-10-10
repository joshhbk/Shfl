import Foundation

public nonisolated struct Song: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let artist: String
    public let albumTitle: String
    public let artworkURL: URL?
    public let playCount: Int
    public let lastPlayedDate: Date?

    public init(
        id: String,
        title: String,
        artist: String,
        albumTitle: String,
        artworkURL: URL?,
        playCount: Int = 0,
        lastPlayedDate: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.albumTitle = albumTitle
        self.artworkURL = artworkURL
        self.playCount = playCount
        self.lastPlayedDate = lastPlayedDate
    }
}
