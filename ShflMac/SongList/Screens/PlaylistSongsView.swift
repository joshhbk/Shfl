import ShflCore
import ShflDesign
import SwiftUI

struct PlaylistSongsView: View {
    @State private var songs: PlaylistDetailViewModel
    @State private var search: ScopedSearch

    private static let columns: [ListColumn] = [.artwork, .title, .detail, .time, .accessory]

    init(songs: PlaylistDetailViewModel) {
        _songs = State(wrappedValue: songs)
        _search = State(wrappedValue: ScopedSearch(prompt: "Search in \(songs.playlistName)"))
    }

    var body: some View {
        let shown = songs.songs.filter { $0.matches(search.text) }
        SongList(songs: shown) {
            ListColumns(Self.columns) {
                ColumnLabel("Title").listColumn(.title)
                ColumnLabel("Album").listColumn(.detail)
                ColumnLabel("Time").listColumn(.time)
            }
        } row: { item in
            SongRow(item, stat: nil, columns: Self.columns) {
                SongArtwork(song: item.song, size: ArtworkSize.songRow).listColumn(.artwork)
                SongTitles(item, subtitle: item.song.artist).listColumn(.title)
                RowDetail(item.song.albumTitle).listColumn(.detail)
                RowDuration(item.song.duration).listColumn(.time)
                PickToggle(item).listColumn(.accessory)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            CollectionHeader(
                songs.playlistName,
                subtitle: SongCount.subtitle(songs.songs.count, isLoaded: songs.hasLoadedAllSongs)
            ) {
                PlaylistArtwork(playlist: songs.playlist, size: ArtworkSize.collection)
            } actions: {
                AddAllButton(songs: songs.songs, isLoaded: songs.hasLoadedAllSongs, owner: songs.playlistName)
            }
        }
        .overlay { emptyState(shown: shown) }
        .navigationTitle(songs.playlistName)
        .toolbar(removing: .title)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Breadcrumb(parent: "Playlists", title: songs.playlistName)
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
                EmptyState("No songs in \(songs.playlistName) match “\(search.text)”", message: "Check the spelling, or search your whole library from Songs.") {
                    Button("Clear Search") { search.text = "" }
                }
            } else if songs.hasLoadedAllSongs {
                EmptyState("This playlist is empty", message: "Add songs to it in the Music app.") {}
            }
        }
    }
}
