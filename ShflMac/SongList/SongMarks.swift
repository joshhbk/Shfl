import ShflCore

/// What a song list row shows about one song's place in your picks and the session.
struct SongMark: Equatable {
    enum Pick: Equatable {
        case picked
        case open
        /// Not picked, and there's no room to pick it.
        case full
    }

    let pick: Pick
    let isPlaying: Bool
    let joinsNextShuffle: Bool

    var isPicked: Bool { pick == .picked }
}

/// Resolved once per list, outside the rows: AppKit builds rows for accessibility without the environment.
struct SongMarks: Equatable {
    private let pickedIDs: Set<String>
    private let isFull: Bool
    private let playingID: String?
    private let joiningNextShuffle: Set<String>

    init(pickedIDs: Set<String>, isFull: Bool, timeline: SessionTimeline) {
        self.pickedIDs = pickedIDs
        self.isFull = isFull
        playingID = timeline.current?.id
        joiningNextShuffle = timeline.changes.joiningNextShuffle
    }

    subscript(song: Song) -> SongMark {
        let isPicked = pickedIDs.contains(song.id)
        return SongMark(
            pick: isPicked ? .picked : isFull ? .full : .open,
            isPlaying: song.id == playingID,
            joinsNextShuffle: joiningNextShuffle.contains(song.id)
        )
    }
}

/// A row's song, its mark and the one action every row offers.
struct SongItem {
    let song: Song
    let mark: SongMark
    let togglePick: () -> Void
}
