import ShflAppleMusicUI
import ShflCore
import ShflDesign
import SwiftUI

struct PlaylistsView: View {
    @State private var openPlaylist: Playlist?
    @Environment(\.screenFactories) private var screens

    var body: some View {
        PlaylistList { openPlaylist = $0 }
            .navigationTitle("Playlists")
            .drillDown(item: $openPlaylist) { playlist in
                PlaylistSongsView(songs: screens.makeSongs(in: playlist))
            }
    }
}

private struct PlaylistList: View {
    let open: (Playlist) -> Void

    @Environment(LibraryBrowser.self) private var browser

    private static let columns: [ListColumn] = [.artwork, .title, .accessory]

    private var isSearching: Bool { !browser.searchText.isEmpty }
    private var playlists: [Playlist] { isSearching ? browser.playlistSearchResults : browser.playlists }

    var body: some View {
        List(playlists) { playlist in
            Button { open(playlist) } label: {
                ListColumns(Self.columns) {
                    PlaylistArtwork(playlist: playlist, size: ArtworkSize.songRow).listColumn(.artwork)
                    Text(playlist.name)
                        .font(.bodyEmphasis)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .listColumn(.title)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .listColumn(.accessory)
                }
                .frame(minHeight: SongListMetrics.rowHeight)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .listRowInsets(EdgeInsets(top: 0, leading: SongListMetrics.rowInset, bottom: 0, trailing: SongListMetrics.rowInset))
            .accessibilityIdentifier("mac.playlists.row.\(playlist.id)")
            .onAppear {
                if playlist.id == playlists.last?.id { loadMore() }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .contentSurface()
        .accessibilityIdentifier("mac.playlists.list")
        .overlay { emptyState }
    }

    @ViewBuilder
    private var emptyState: some View {
        if playlists.isEmpty {
            if browser.playlistsLoading || browser.playlistSearchLoading {
                ProgressView()
            } else if isSearching && browser.hasPlaylistSearchedOnce {
                EmptyState("No playlists match “\(browser.searchText)”", message: "Check the spelling, or search your songs instead.") {
                    Button("Clear Search") { browser.searchText = "" }
                }
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

struct PlaylistArtwork: View {
    let playlist: Playlist
    let size: CGFloat

    var body: some View {
        ArtworkFrame(size: size) {
            ArtworkView(subject: .playlist(id: playlist.id), size: size) { ArtworkPlaceholder(systemImage: "music.note.list") }
        }
    }
}
