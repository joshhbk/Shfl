import ShflCore
import ShflDesign
import SwiftUI

struct PlaylistSongsView: View {
    @State private var songs: PlaylistDetailViewModel

    private static let columns: [ListColumn] = [.artwork, .title, .detail, .time, .accessory]

    init(songs: PlaylistDetailViewModel) {
        _songs = State(wrappedValue: songs)
    }

    var body: some View {
        SongList(songs: songs.songs, onReachEnd: { Task { await songs.loadMorePages() } }) {
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
        .overlay {
            if songs.songs.isEmpty && songs.isLoading { ProgressView() }
        }
        .navigationTitle(songs.playlistName)
        .task { await songs.loadInitialPage() }
    }
}
