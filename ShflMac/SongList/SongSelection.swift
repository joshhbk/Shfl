import ShflCore
import SwiftUI

/// The selected rows of the song list that has focus, in list order.
struct SongSelection: Equatable {
    let songs: [Song]
    let canAdd: Bool
    let canRemove: Bool

    init(songs: [Song], marks: SongMarks) {
        self.songs = songs
        canAdd = songs.contains { !marks[$0].isPicked }
        canRemove = songs.contains { marks[$0].isPicked }
    }
}

extension FocusedValues {
    @Entry var songSelection: SongSelection?
}
