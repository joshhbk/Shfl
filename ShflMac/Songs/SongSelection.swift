import ShflCore
import SwiftUI

struct SongSelection: Equatable {
    let songs: [Song]
}

extension FocusedValues {
    @Entry var songSelection: SongSelection?
}
