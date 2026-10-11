import AppKit
import ShflCore
import ShflDesign
import SwiftUI

struct LibrarySongsView: View {
    @Environment(LibraryBrowser.self) private var browser
    @Environment(\.showPlace) private var showPlace

    private static let stats: [SongStat] = [.plays, .lastPlayed, .added]
    private static let columns: [ListColumn] = [.artwork, .title, .detail] + stats.map(\.column) + [.time, .accessory]

    private var isSearching: Bool { !browser.searchText.isEmpty }

    var body: some View {
        SongList(songs: isSearching ? browser.searchResults : browser.browseSongs, onReachEnd: loadMore) {
            ListColumns(Self.columns) {
                SortHeader("Title", sort: .alphabetical).listColumn(.title)
                ColumnLabel("Album").listColumn(.detail)
                ForEach(Self.stats, id: \.self) { stat in
                    SortHeader(stat.title, sort: stat.sort).listColumn(stat.column)
                }
                ColumnLabel("Time").listColumn(.time)
            }
        } row: { item in
            SongRow(item, stat: SongStat(browser.sortOption), columns: Self.columns) {
                SongArtwork(song: item.song, size: ArtworkSize.songRow).listColumn(.artwork)
                SongTitles(item, subtitle: item.song.artist).listColumn(.title)
                RowDetail(item.song.albumTitle).listColumn(.detail)
                ForEach(Self.stats, id: \.self) { stat in
                    RowStat(stat, of: item.song).listColumn(stat.column)
                }
                RowDuration(item.song.duration).listColumn(.time)
                PickToggle(item).listColumn(.accessory)
            }
        }
        .overlay { emptyState }
        .task { await browser.loadInitialPage() }
    }

    @ViewBuilder
    private var emptyState: some View {
        if isSearching {
            if browser.searchResults.isEmpty && browser.hasSearchedOnce && !browser.searchLoading {
                EmptyState(
                    "No songs match “\(browser.searchText)”",
                    message: "Check the spelling, or try the same search in Artists."
                ) {
                    Button("Clear Search") { browser.searchText = "" }
                    Button("Search Artists") { showPlace(.artists) }
                }
            }
        } else if browser.browseSongs.isEmpty {
            if browser.browseLoading {
                ProgressView()
            } else {
                EmptyState(
                    "No songs in your library yet",
                    message: "Shuffled plays what’s in your Apple Music library. Add music in the Music app and it shows up here."
                ) {
                    EmptyStateSymbol("music.note")
                } actions: {
                    Button("Open Music", action: openMusic)
                }
            }
        }
    }

    private func openMusic() {
        guard let music = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Music") else { return }
        NSWorkspace.shared.openApplication(at: music, configuration: NSWorkspace.OpenConfiguration())
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

/// A heading that sorts the library by its column. Each order runs one way, the way the catalog offers it.
private struct SortHeader: View {
    let title: String
    let sort: SortOption

    @Environment(LibraryBrowser.self) private var browser

    init(_ title: String, sort: SortOption) {
        self.title = title
        self.sort = sort
    }

    var body: some View {
        Button(title) { browser.chooseSortOption(sort) }
            .buttonStyle(.columnSort(isSorted: browser.sortOption == sort))
            .help("Sort by \(sort.displayName)")
            .accessibilityIdentifier("mac.songs.sort.\(sort.rawValue)")
    }
}
