import Foundation
import ShflCore

enum DeterministicSongs {
    static func make(_ count: Int, start: Int = 1) -> [Song] {
        (start..<(start + count)).map { index in
            Song(
                id: "song-\(index)",
                title: "Song \(index)",
                artist: "Artist \(index % 7)",
                albumTitle: "Album \(index % 5)",
                artworkURL: nil,
                playCount: index,
                duration: TimeInterval(150 + index),
                dateAdded: Date(timeIntervalSinceReferenceDate: 812_000_000 - Double(index) * 86_400)
            )
        }
    }
}
