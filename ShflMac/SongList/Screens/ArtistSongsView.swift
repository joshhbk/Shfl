import ShflCore
import ShflDesign
import SwiftUI

struct ArtistSongsView: View {
    @State private var songs: ArtistDetailViewModel
    @State private var search: ScopedSearch
    @State private var order = SortOption.mostPlayed

    private static let columns: [ListColumn] = [.artwork, .title, SongStat.plays.column, .time, .accessory]

    init(songs: ArtistDetailViewModel) {
        _songs = State(wrappedValue: songs)
        _search = State(wrappedValue: ScopedSearch(prompt: "Search in \(songs.artistName)"))
    }

    var body: some View {
        let shown = SongOrder.sorted(songs.songs.filter { $0.matches(search.text) }, by: order)
        SongList(songs: shown, columns: Self.columns, stat: .plays) {
            Button("Title") { order = .alphabetical }
                .buttonStyle(.columnSort(isSorted: order == .alphabetical))
                .listColumn(.title)
            Button(SongStat.plays.title) { order = .mostPlayed }
                .buttonStyle(.columnSort(isSorted: order == .mostPlayed))
                .listColumn(SongStat.plays.column)
            ColumnLabel("Time").listColumn(.time)
        } cells: { item in
            SongArtwork(song: item.song, size: ArtworkSize.songRow).listColumn(.artwork)
            SongTitles(item, subtitle: item.song.albumTitle).listColumn(.title)
            RowStat(.plays, of: item.song).listColumn(SongStat.plays.column)
            RowDuration(item.song.duration).listColumn(.time)
            PickToggle(item).listColumn(.accessory)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            ArtistHeader(songs: songs)
        }
        .overlay { emptyState(shown: shown) }
        .navigationTitle(songs.artistName)
        .toolbar(removing: .title)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Breadcrumb(parent: "Artists", title: songs.artistName)
            }
        }
        .searchScope(search)
        .task { await songs.loadAllSongs() }
    }

    @ViewBuilder
    private func emptyState(shown: [Song]) -> some View {
        if shown.isEmpty {
            if songs.songs.isEmpty && songs.isLoading {
                ProgressView()
            } else if !search.text.isEmpty {
                EmptyState("No songs by \(songs.artistName) match “\(search.text)”", message: "Check the spelling, or search your whole library from Songs.") {
                    Button("Clear Search") { search.text = "" }
                }
            }
        }
    }
}

private struct ArtistHeader: View {
    let songs: ArtistDetailViewModel

    var body: some View {
        CollectionHeader(
            songs.artistName,
            subtitle: SongCount.subtitle(songs.songs.count, isLoaded: songs.hasLoadedAllSongs)
        ) {
            ArtistArtwork(artist: songs.artist, size: ArtworkSize.collection)
        } actions: {
            AddAllButton(songs: songs.songs, isLoaded: songs.hasLoadedAllSongs, owner: songs.artistName)
        }
    }
}
