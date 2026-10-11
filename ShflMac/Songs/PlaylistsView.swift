import ShflCore
import SwiftUI

struct PlaylistsView: View {
    @Environment(\.screenFactories) private var screens

    var body: some View {
        NavigationStack {
            PlaylistList()
                .navigationTitle("Playlists")
                .navigationDestination(for: Playlist.self) { playlist in
                    PlaylistSongsView(songs: screens.makeSongs(in: playlist))
                        .toolbar { LibraryToolbar() }
                }
        }
    }
}

private struct PlaylistList: View {
    @Environment(LibraryBrowser.self) private var browser

    private var isSearching: Bool { !browser.searchText.isEmpty }
    private var playlists: [Playlist] { isSearching ? browser.playlistSearchResults : browser.playlists }

    var body: some View {
        List(playlists) { playlist in
            NavigationLink(value: playlist) {
                Label(playlist.name, systemImage: "music.note.list")
            }
            .accessibilityIdentifier("mac.playlists.row.\(playlist.id)")
            .onAppear {
                if playlist.id == playlists.last?.id { loadMore() }
            }
        }
        .accessibilityIdentifier("mac.playlists.list")
        .overlay {
            if playlists.isEmpty && (browser.playlistsLoading || browser.playlistSearchLoading) {
                ProgressView()
            }
        }
    }

    private func loadMore() {
        Task {
            if isSearching {
                await browser.loadMorePlaylistSearchResults()
            } else {
                await browser.loadMorePlaylists()
            }
        }
    }
}
