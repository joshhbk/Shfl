import Foundation
import SwiftData

@Model
final class PersistedSong {
    @Attribute(.unique) var songId: String
    var title: String
    var artist: String
    var albumTitle: String
    var artworkURLString: String?
    var orderIndex: Int

    init(songId: String, title: String, artist: String, albumTitle: String, artworkURLString: String?, orderIndex: Int) {
        self.songId = songId
        self.title = title
        self.artist = artist
        self.albumTitle = albumTitle
        self.artworkURLString = artworkURLString
        self.orderIndex = orderIndex
    }

    func toSong() -> Song {
        Song(
            id: songId,
            title: title,
            artist: artist,
            albumTitle: albumTitle,
            artworkURL: artworkURLString.flatMap { URL(string: $0) }
        )
    }

    static func from(_ song: Song, orderIndex: Int) -> PersistedSong {
        PersistedSong(
            songId: song.id,
            title: song.title,
            artist: song.artist,
            albumTitle: song.albumTitle,
            artworkURLString: song.artworkURL?.absoluteString,
            orderIndex: orderIndex
        )
    }
}
