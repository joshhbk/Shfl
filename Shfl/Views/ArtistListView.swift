import SwiftUI

struct ArtistListView: View {
    @Bindable var viewModel: LibraryBrowserViewModel
    let musicService: MusicService
    @Binding var selectedSongIds: Set<String>
    let isAtCapacity: Bool
    let onToggleSong: (Song) -> Void

    // Optional search results — when provided, show these instead of browse data
    var searchResults: [Artist]? = nil
    var hasMoreSearchResults: Bool = false
    var onLoadMore: (() -> Void)? = nil

    private var displayedArtists: [Artist] {
        searchResults ?? viewModel.artists
    }

    private var hasMore: Bool {
        searchResults != nil ? hasMoreSearchResults : viewModel.hasMoreArtists
    }

    var body: some View {
        if searchResults == nil && viewModel.artistsLoading && viewModel.artists.isEmpty {
            skeletonList
        } else if displayedArtists.isEmpty {
            ContentUnavailableView(
                "No Artists in Library",
                systemImage: "person.2",
                description: Text("Add music to your Apple Music library to see artists here")
            )
        } else {
            artistList
        }
    }

    private var artistList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(displayedArtists) { artist in
                    NavigationLink(value: artist) {
                        ArtistRow(artist: artist)
                    }
                    .buttonStyle(.plain)
                    Divider().padding(.leading, 72)
                }

                if hasMore {
                    ProgressView()
                        .padding()
                        .onAppear {
                            if let onLoadMore {
                                onLoadMore()
                            } else {
                                Task { await viewModel.loadMoreArtists() }
                            }
                        }
                }
            }
        }
        .navigationDestination(for: Artist.self) { artist in
            ArtistDetailView(
                artistName: artist.name,
                musicService: musicService,
                selectedSongIds: $selectedSongIds,
                isAtCapacity: isAtCapacity,
                onToggleSong: onToggleSong
            )
        }
    }

    private var skeletonList: some View { SkeletonList() }
}

private struct ArtistRow: View {
    let artist: Artist

    var body: some View {
        HStack(spacing: 12) {
            EntityArtwork(entityId: artist.id, type: .artist)

            Text(artist.name)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
    }
}
