import Foundation
import MusicKit
import ShflCore

extension ShflCore.Song {
    nonisolated init(_ song: MusicKit.Song, artworkURL: URL? = nil) {
        self.init(
            id: song.id.rawValue,
            title: song.title,
            artist: song.artistName,
            albumTitle: song.albumTitle ?? "",
            artworkURL: artworkURL,
            playCount: song.playCount ?? 0,
            lastPlayedDate: song.lastPlayedDate,
            duration: song.duration,
            dateAdded: song.libraryAddedDate
        )
    }
}
