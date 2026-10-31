import ShflCore
import SwiftUI

/// The selected rows of the song list that has focus, in list order.
struct SongSelection: Equatable {
    enum PickAction: Equatable {
        case add
        case remove
        /// Some songs aren't picked, and there's no room for any of them.
        case full
    }

    let songs: [Song]
    /// What ↩ and the selection bar do.
    let action: PickAction
    let canRemove: Bool

    init(songs: [Song], marks: SongMarks) {
        self.songs = songs
        let picks = songs.map { marks[$0].pick }
        canRemove = picks.contains(.picked)
        action = if !picks.contains(where: { $0 != .picked }) {
            .remove
        } else if picks.contains(.full) {
            .full
        } else {
            .add
        }
    }
}

extension FocusedValues {
    @Entry var songSelection: SongSelection?
}
