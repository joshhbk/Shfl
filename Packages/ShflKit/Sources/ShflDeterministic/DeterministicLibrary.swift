import Foundation
import ShflCore

/// A made-up Apple Music library for previews and deterministic launches.
public nonisolated struct DeterministicLibrary: Sendable {
    public var songs: [Song]
    public var playlists: [Playlist]
    /// Each playlist's songs, keyed by playlist id. A playlist missing here
    /// is empty.
    public var playlistSongs: [String: [Song]]

    public init(
        songs: [Song] = [],
        playlists: [Playlist] = [],
        playlistSongs: [String: [Song]] = [:]
    ) {
        self.songs = songs
        self.playlists = playlists
        self.playlistSongs = playlistSongs
    }

    public static let empty = DeterministicLibrary()

    /// What `--deterministic` launches browse and shuffle. Playback
    /// scenarios depend on these songs and their play counts.
    public static let launch: DeterministicLibrary = {
        let songs = [
            Song(
                id: "scenario-low-tide",
                title: "Low Tide",
                artist: "Harbour Lights",
                albumTitle: "Deterministic Sessions",
                artworkURL: nil,
                playCount: 0
            ),
            Song(
                id: "scenario-second-wind",
                title: "Second Wind",
                artist: "Northern Static",
                albumTitle: "Deterministic Sessions",
                artworkURL: nil,
                playCount: 1
            ),
            Song(
                id: "scenario-afterglow",
                title: "Afterglow",
                artist: "Paper Satellites",
                albumTitle: "Deterministic Sessions",
                artworkURL: nil,
                playCount: 2
            )
        ]
        return DeterministicLibrary(
            songs: songs,
            playlists: [Playlist(id: "scenario-playlist", name: "Deterministic Sessions")],
            playlistSongs: ["scenario-playlist": songs]
        )
    }()

    /// Ten well-known songs in three playlists, enough to fill a picker.
    public static let sample: DeterministicLibrary = {
        let songs = [
            Song(id: "1", title: "Bohemian Rhapsody", artist: "Queen", albumTitle: "A Night at the Opera", artworkURL: nil, playCount: 142),
            Song(id: "2", title: "Stairway to Heaven", artist: "Led Zeppelin", albumTitle: "Led Zeppelin IV", artworkURL: nil, playCount: 98),
            Song(id: "3", title: "Hotel California", artist: "Eagles", albumTitle: "Hotel California", artworkURL: nil, playCount: 76),
            Song(id: "4", title: "Comfortably Numb", artist: "Pink Floyd", albumTitle: "The Wall", artworkURL: nil, playCount: 63),
            Song(id: "5", title: "Sweet Child O' Mine", artist: "Guns N' Roses", albumTitle: "Appetite for Destruction", artworkURL: nil, playCount: 55),
            Song(id: "6", title: "Wish You Were Here", artist: "Pink Floyd", albumTitle: "Wish You Were Here", artworkURL: nil, playCount: 49),
            Song(id: "7", title: "Back in Black", artist: "AC/DC", albumTitle: "Back in Black", artworkURL: nil, playCount: 41),
            Song(id: "8", title: "Imagine", artist: "John Lennon", albumTitle: "Imagine", artworkURL: nil, playCount: 37),
            Song(id: "9", title: "Hey Jude", artist: "The Beatles", albumTitle: "Hey Jude", artworkURL: nil, playCount: 30),
            Song(id: "10", title: "Smells Like Teen Spirit", artist: "Nirvana", albumTitle: "Nevermind", artworkURL: nil, playCount: 25),
        ]
        return DeterministicLibrary(
            songs: songs,
            playlists: [
                Playlist(id: "p1", name: "Classic Rock Hits"),
                Playlist(id: "p2", name: "Road Trip Mix"),
                Playlist(id: "p3", name: "Chill Vibes"),
            ],
            playlistSongs: [
                "p1": Array(songs.prefix(3)),
                "p2": Array(songs.dropFirst(3).prefix(3)),
                "p3": Array(songs.dropFirst(6).prefix(3))
            ]
        )
    }()
}

/// Where deterministic playback starts. Time moves only when a test
/// advances it, so a preview stays exactly where this puts it.
public nonisolated struct DeterministicPlayback: Sendable {
    public var state: PlaybackState
    public var time: TimeInterval
    public var duration: TimeInterval

    public init(state: PlaybackState = .empty, time: TimeInterval = 0, duration: TimeInterval = 180) {
        self.state = state
        self.time = time
        self.duration = duration
    }
}

extension DeterministicMusicService {
    public init(library: DeterministicLibrary, playback: DeterministicPlayback = DeterministicPlayback()) {
        self.init(
            configuration: Configuration(
                librarySongs: library.songs,
                libraryPlaylists: library.playlists,
                playlistSongs: library.playlistSongs,
                playbackDuration: playback.duration,
                playbackTime: playback.time,
                playbackState: playback.state
            )
        )
    }
}
