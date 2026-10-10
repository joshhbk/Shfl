import ShflCore
import SwiftUI

struct ArtistsView: View {
    @Environment(\.screenFactories) private var screens

    var body: some View {
        NavigationStack {
            ArtistList()
                .navigationTitle("Artists")
                .navigationDestination(for: Artist.self) { artist in
                    ArtistSongsView(songs: screens.makeSongs(by: artist))
                        .toolbar { LibraryToolbar() }
                }
        }
    }
}

private struct ArtistList: View {
    @Environment(LibraryBrowser.self) private var browser

    private var isSearching: Bool { !browser.searchText.isEmpty }
    private var artists: [Artist] { isSearching ? browser.artistSearchResults : browser.artists }

    var body: some View {
        List(artists) { artist in
            NavigationLink(value: artist) {
                Label(artist.name, systemImage: "music.mic")
            }
            .accessibilityIdentifier("mac.artists.row.\(artist.id)")
            .onAppear {
                if artist.id == artists.last?.id { loadMore() }
            }
        }
        .accessibilityIdentifier("mac.artists.list")
        .overlay {
            if artists.isEmpty && (browser.artistsLoading || browser.artistSearchLoading) {
                ProgressView()
            }
        }
    }

    private func loadMore() {
        Task {
            if isSearching {
                await browser.loadMoreArtistSearchResults()
            } else {
                await browser.loadMoreArtists()
            }
        }
    }
}

private struct ArtistSongsView: View {
    @State private var songs: ArtistDetailViewModel
    @Environment(DraftEditing.self) private var drafting

    init(songs: ArtistDetailViewModel) {
        _songs = State(wrappedValue: songs)
    }

    var body: some View {
        SongsTable(
            songs: songs.songs,
            onReachEnd: { Task { await songs.loadMorePages() } }
        ) { selected in
            AddToSelectedButton(songs: selected, drafting: drafting)
        }
        .overlay {
            if songs.songs.isEmpty && songs.isLoading { ProgressView() }
        }
        .navigationTitle(songs.artistName)
        .task { await songs.loadInitialPage() }
    }
}
