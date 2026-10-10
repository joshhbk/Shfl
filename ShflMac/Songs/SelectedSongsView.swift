import ShflCore
import SwiftUI

struct SelectedSongsView: View {
    @State private var sortOrder: [KeyPathComparator<Song>] = []
    @Environment(DraftEditing.self) private var drafting
    @Environment(LibraryBrowser.self) private var browser

    var body: some View {
        SongsTable(songs: shownSongs, sortOrder: $sortOrder)
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

    private var shownSongs: [Song] {
        let query = browser.searchText
        let songs = query.isEmpty ? drafting.draft.songs : drafting.draft.songs.filter {
            $0.title.localizedStandardContains(query)
                || $0.artist.localizedStandardContains(query)
                || $0.albumTitle.localizedStandardContains(query)
        }
        return songs.sorted(using: sortOrder)
    }
}
