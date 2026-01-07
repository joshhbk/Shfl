import Foundation

struct Song: Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let artist: String
    let albumTitle: String
    let artworkURL: URL?
    let playCount: Int
    let lastPlayedDate: Date?

    init(
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
