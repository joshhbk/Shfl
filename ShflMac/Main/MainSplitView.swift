import ShflCore
import SwiftUI

struct MainSplitView: View {
    let makeArtistSongs: (Artist) -> ArtistDetailViewModel
    let makePlaylistSongs: (Playlist) -> PlaylistDetailViewModel

    @State private var selection: SidebarItem? = .songs
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @Environment(LibraryBrowser.self) private var browser

    var body: some View {
        @Bindable var browser = browser
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selection: $selection)
        } detail: {
            DetailColumn(
                item: selection ?? .songs,
                makeArtistSongs: makeArtistSongs,
                makePlaylistSongs: makePlaylistSongs
            )
        }
        .searchable(text: $browser.searchText, placement: .toolbar, prompt: searchPrompt)
        .onChange(of: selection, initial: true) {
            browser.activeLane = (selection ?? .songs).libraryLane
        }
    }

    private var searchPrompt: String {
        switch selection ?? .songs {
        case .songs: "Search Songs"
        case .artists: "Search Artists"
        case .playlists: "Search Playlists"
        case .selected: "Search Selected"
        case .upNext: "Search"
        }
    }
}
