import ShflCore
import ShflDesign
import SwiftUI

struct LibrarySongsView: View {
    @Environment(LibraryBrowser.self) private var browser

    private static let columns = Set(ListColumn.allCases)

    private var isSearching: Bool { !browser.searchText.isEmpty }

    var body: some View {
        let stat = SongStat(browser.sortOption)
        SongList(songs: isSearching ? browser.searchResults : browser.browseSongs, onReachEnd: loadMore) {
            ListColumns(Self.columns) {
                ColumnLabel("Title").listColumn(.title)
                ColumnLabel("Album").listColumn(.detail)
                ColumnLabel(stat.title).listColumn(.stat)
                ColumnLabel("Time").listColumn(.time)
            }
        } row: { item in
            SongRow(item, stat: stat, columns: Self.columns) {
                SongArtwork(song: item.song, size: ArtworkSize.songRow).listColumn(.artwork)
                SongTitles(item, subtitle: item.song.artist).listColumn(.title)
                RowDetail(item.song.albumTitle).listColumn(.detail)
                RowStat(stat, of: item.song).listColumn(.stat)
                RowDuration(item.song.duration).listColumn(.time)
                PickToggle(item).listColumn(.accessory)
            }
        }
        .overlay { emptyState }
        .toolbar {
            ToolbarItem { SortMenu() }
        }
        .task { await browser.loadInitialPage() }
    }

    @ViewBuilder
    private var emptyState: some View {
        if isSearching {
            if browser.searchResults.isEmpty && browser.hasSearchedOnce && !browser.searchLoading {
                ContentUnavailableView.search(text: browser.searchText)
            }
        } else if browser.browseSongs.isEmpty {
            if browser.browseLoading {
                ProgressView()
            } else {
                ContentUnavailableView("No Songs", systemImage: "music.note", description: Text("Songs you add to your Apple Music library appear here."))
            }
        }
    }

    private func loadMore() {
        Task {
            if isSearching {
                await browser.loadMoreSearchResults()
            } else {
                await browser.loadMorePages()
            }
        }
    }
}

private struct SortMenu: View {
    @Environment(LibraryBrowser.self) private var browser

    var body: some View {
        Menu {
            SongSortPicker(selection: browser.sortSelection)
                .pickerStyle(.inline)
        } label: {
            Text("Sort: \(browser.sortOption.displayName)")
        }
        .help("Sort Songs")
        .accessibilityIdentifier("mac.toolbar.sort")
    }
}
