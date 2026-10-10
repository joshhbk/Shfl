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
                playCount: index
            )
        }
    }
}
