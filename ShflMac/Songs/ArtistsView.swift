import ShflAppleMusicUI
import ShflCore
import ShflDesign
import SwiftUI

struct ArtistsView: View {
    @State private var openArtist: Artist?
    @Environment(\.screenFactories) private var screens

    var body: some View {
        ArtistList { openArtist = $0 }
            .navigationTitle("Artists")
            .drillDown(item: $openArtist) { artist in
                ArtistSongsView(songs: screens.makeSongs(by: artist))
            }
    }
}

private struct ArtistList: View {
    let open: (Artist) -> Void

    @Environment(LibraryBrowser.self) private var browser

    private static let columns: [ListColumn] = [.artwork, .title, .accessory]

    private var isSearching: Bool { !browser.searchText.isEmpty }
    private var artists: [Artist] { isSearching ? browser.artistSearchResults : browser.artists }

    var body: some View {
        List(artists) { artist in
            Button { open(artist) } label: {
                ListColumns(Self.columns) {
                    ArtistArtwork(artist: artist, size: ArtworkSize.songRow).listColumn(.artwork)
                    Text(artist.name)
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
            .accessibilityIdentifier("mac.artists.row.\(artist.id)")
            .onAppear {
                if artist.id == artists.last?.id { loadMore() }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .contentSurface()
        .accessibilityIdentifier("mac.artists.list")
        .overlay { emptyState }
    }

    @ViewBuilder
    private var emptyState: some View {
        if artists.isEmpty {
            if browser.artistsLoading || browser.artistSearchLoading {
                ProgressView()
            } else if isSearching && browser.hasArtistSearchedOnce {
                EmptyState("No artists match “\(browser.searchText)”", message: "Check the spelling, or search your songs instead.") {
                    Button("Clear Search") { browser.searchText = "" }
                }
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

/// An artist's picture in a circle, or their monogram when the library has none.
struct ArtistArtwork: View {
    let artist: Artist
    let size: CGFloat

    var body: some View {
        RoundArtworkFrame(size: size) {
            ArtworkView(subject: .artist(id: artist.id), size: size) { MonogramArtwork(artist.name) }
        }
    }
}
