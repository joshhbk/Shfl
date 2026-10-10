import ShflCore
import SwiftUI

struct ArtistsView: View {
    let makeSongs: (Artist) -> ArtistDetailViewModel

    var body: some View {
        NavigationStack {
            ArtistList()
                .navigationTitle("Artists")
                .navigationDestination(for: Artist.self) { artist in
                    ArtistSongsView(songs: makeSongs(artist))
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
    @State private var sortOrder: [KeyPathComparator<Song>] = []

    init(songs: ArtistDetailViewModel) {
        _songs = State(wrappedValue: songs)
    }

    var body: some View {
        SongsTable(
            songs: songs.songs.sorted(using: sortOrder),
            sortOrder: $sortOrder,
            onReachEnd: { Task { await songs.loadMorePages() } }
        )
        .overlay {
            if songs.songs.isEmpty && songs.isLoading { ProgressView() }
        }
        .navigationTitle(songs.artistName)
        .task { await songs.loadInitialPage() }
    }
}
