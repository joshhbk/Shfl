import ShflCore
import SwiftUI

struct LibrarySongsView: View {
    @Environment(LibraryBrowser.self) private var browser
    @Environment(DraftEditing.self) private var drafting

    private var isSearching: Bool { !browser.searchText.isEmpty }

    var body: some View {
        SortableSongsTable(
            songs: isSearching ? browser.searchResults : browser.browseSongs,
            sortOrder: sortOrder,
            onReachEnd: loadMore
        ) { songs in
            AddToSelectedButton(songs: songs, drafting: drafting)
        }
        .overlay { emptyState }
        .task { await browser.loadInitialPage() }
    }

    private var sortOrder: Binding<[KeyPathComparator<Song>]> {
        Binding(
            get: { LibrarySongOrder.sortOrder(for: browser.sortOption) },
            set: { newOrder in
                if let option = LibrarySongOrder.option(for: newOrder) {
                    browser.chooseSortOption(option)
                }
            }
        )
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
