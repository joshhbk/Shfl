import ShflCore
import ShflDesign
import SwiftUI

struct ArtistSongsView: View {
    @State private var songs: ArtistDetailViewModel

    private static let columns: Set<ListColumn> = [.artwork, .title, .stat, .time, .accessory]

    init(songs: ArtistDetailViewModel) {
        _songs = State(wrappedValue: songs)
    }

    var body: some View {
        SongList(songs: songs.songs, onReachEnd: { Task { await songs.loadMorePages() } }) {
            ListColumns(Self.columns) {
                ColumnLabel("Title").listColumn(.title)
                ColumnLabel(SongStat.plays.title).listColumn(.stat)
                ColumnLabel("Time").listColumn(.time)
            }
        } row: { item in
            SongRow(item, stat: .plays, columns: Self.columns) {
                SongArtwork(song: item.song, size: ArtworkSize.songRow).listColumn(.artwork)
                SongTitles(item, subtitle: item.song.albumTitle).listColumn(.title)
                RowStat(.plays, of: item.song).listColumn(.stat)
                RowDuration(item.song.duration).listColumn(.time)
                PickToggle(item).listColumn(.accessory)
            }
        }
        .overlay {
            if songs.songs.isEmpty && songs.isLoading { ProgressView() }
        }
        .navigationTitle(songs.artistName)
        .task { await songs.loadInitialPage() }
    }
}
