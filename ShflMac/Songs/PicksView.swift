import ShflCore
import SwiftUI

struct PicksView: View {
    @State private var sortOrder: [KeyPathComparator<Song>] = []
    @Environment(DraftEditing.self) private var drafting
    @Environment(LibraryBrowser.self) private var browser

    var body: some View {
        SortableSongsTable(
            songs: drafting.draft.songs(matching: browser.searchText).sorted(using: sortOrder),
            sortOrder: Binding(get: { sortOrder }, set: { sortOrder = LibrarySongOrder.oneWay($0) })
        ) { songs in
            RemoveFromPicksButton(songs: songs, drafting: drafting)
        }
        .overlay {
            if drafting.draft.isEmpty {
                ContentUnavailableView(
                    "No Picks Yet",
                    systemImage: "checkmark.circle",
                    description: Text("Add songs from your library, or use Autofill.")
                )
            }
        }
    }
}
