import ShflCore
import SwiftUI

struct DetailColumn: View {
    let item: SidebarItem
    let makeArtistSongs: (Artist) -> ArtistDetailViewModel
    let makePlaylistSongs: (Playlist) -> PlaylistDetailViewModel

    var body: some View {
        switch item {
        case .songs:
            LibrarySongsView()
                .navigationTitle("Songs")
        case .artists:
            ArtistsView(makeSongs: makeArtistSongs)
        case .playlists:
            PlaylistsView(makeSongs: makePlaylistSongs)
        case .selected:
            SelectedSongsView()
                .navigationTitle("Selected")
        case .upNext:
            UpNextView()
                .navigationTitle("Up Next")
        }
    }
}
