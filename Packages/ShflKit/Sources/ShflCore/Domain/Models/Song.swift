import Foundation

public nonisolated struct Song: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let artist: String
    public let albumTitle: String
    public let artworkURL: URL?
    public let playCount: Int
    public let lastPlayedDate: Date?
    public let duration: TimeInterval?
    public let dateAdded: Date?

    /// Whether the title, artist or album contains `query`. An empty query matches everything.
    public func matches(_ query: String) -> Bool {
        query.isEmpty
            || title.localizedStandardContains(query)
            || artist.localizedStandardContains(query)
            || albumTitle.localizedStandardContains(query)
    }

    public init(
        id: String,
        title: String,
        artist: String,
        albumTitle: String,
        artworkURL: URL?,
        playCount: Int = 0,
        lastPlayedDate: Date? = nil,
        duration: TimeInterval? = nil,
        dateAdded: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.albumTitle = albumTitle
        self.artworkURL = artworkURL
        self.playCount = playCount
        self.lastPlayedDate = lastPlayedDate
        self.duration = duration
        self.dateAdded = dateAdded
    }
}
