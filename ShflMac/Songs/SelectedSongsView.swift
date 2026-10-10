import ShflCore
import SwiftUI

struct SelectedSongsView: View {
    @State private var sortOrder: [KeyPathComparator<Song>] = []
    @Environment(DraftEditing.self) private var drafting
    @Environment(LibraryBrowser.self) private var browser

    var body: some View {
        SortableSongsTable(
            songs: drafting.draft.songs(matching: browser.searchText).sorted(using: sortOrder),
            sortOrder: Binding(get: { sortOrder }, set: { sortOrder = LibrarySongOrder.oneWay($0) })
        ) { songs in
            RemoveFromSelectedButton(songs: songs, drafting: drafting)
        }
        .overlay {
            if drafting.draft.isEmpty {
                ContentUnavailableView(
                    "Nothing Selected",
                    systemImage: "checkmark.circle",
                    description: Text("Check songs in your library, or use Autofill.")
                )
            }
        }
    }
}
