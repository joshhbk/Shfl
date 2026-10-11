import ShflCore
import SwiftUI

struct DetailColumn: View {
    let place: SidebarItem

    var body: some View {
        switch place {
        case .songs:
            LibrarySongsView()
                .navigationTitle("Songs")
        case .artists:
            ArtistsView()
        case .playlists:
            PlaylistsView()
        }
    }
}
