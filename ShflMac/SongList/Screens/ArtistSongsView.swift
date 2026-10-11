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
        SongList(songs: shown) {
            ListColumns(Self.columns) {
                Button("Title") { order = .alphabetical }
                    .buttonStyle(.columnSort(isSorted: order == .alphabetical))
                    .listColumn(.title)
                Button(SongStat.plays.title) { order = .mostPlayed }
                    .buttonStyle(.columnSort(isSorted: order == .mostPlayed))
                    .listColumn(SongStat.plays.column)
                ColumnLabel("Time").listColumn(.time)
            }
        } row: { item in
            SongRow(item, stat: .plays, columns: Self.columns) {
                SongArtwork(song: item.song, size: ArtworkSize.songRow).listColumn(.artwork)
                SongTitles(item, subtitle: item.song.albumTitle).listColumn(.title)
                RowStat(.plays, of: item.song).listColumn(SongStat.plays.column)
                RowDuration(item.song.duration).listColumn(.time)
                PickToggle(item).listColumn(.accessory)
            }
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

    @Environment(DraftEditing.self) private var drafting

    var body: some View {
        let isLoaded = songs.hasLoadedAllSongs
        let pickedIDs = drafting.songIDs
        let allPicked = !songs.songs.isEmpty && songs.songs.allSatisfy { pickedIDs.contains($0.id) }
        CollectionHeader(
            songs.artistName,
            subtitle: isLoaded ? SongCount.text(songs.songs.count) : "Loading songs…"
        ) {
            ArtistArtwork(artist: songs.artist, size: ArtworkSize.collection)
        } actions: {
            Button(allPicked ? "All Picked" : "Add All") { drafting.add(songs.songs) }
                .buttonStyle(.primary)
                .disabled(!isLoaded || songs.songs.isEmpty || allPicked)
                .help(allPicked ? "Every song by \(songs.artistName) is in your picks" : "Add every song by \(songs.artistName) to your picks")
                .accessibilityIdentifier("mac.artist.addAll")
        }
    }
}

enum SongCount {
    static func text(_ count: Int) -> String {
        count == 1 ? "1 song" : "\(count.formatted()) songs"
    }
}
