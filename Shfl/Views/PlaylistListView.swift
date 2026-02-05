import SwiftUI

struct PlaylistListView: View {
    @Bindable var viewModel: LibraryBrowserViewModel
    let musicService: MusicService
    @Binding var selectedSongIds: Set<String>
    let isAtCapacity: Bool
    let onToggleSong: (Song) -> Void

    // Optional search results — when provided, show these instead of browse data
    var searchResults: [Playlist]? = nil
    var hasMoreSearchResults: Bool = false
    var onLoadMore: (() -> Void)? = nil

    private var displayedPlaylists: [Playlist] {
        searchResults ?? viewModel.playlists
    }

    private var hasMore: Bool {
        searchResults != nil ? hasMoreSearchResults : viewModel.hasMorePlaylists
    }

    var body: some View {
        if searchResults == nil && viewModel.playlistsLoading && viewModel.playlists.isEmpty {
            skeletonList
        } else if displayedPlaylists.isEmpty {
            ContentUnavailableView(
                "No Playlists in Library",
                systemImage: "music.note.list",
                description: Text("Create playlists in Apple Music to see them here")
            )
        } else {
            playlistList
        }
    }

    private var playlistList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(displayedPlaylists) { playlist in
                    NavigationLink(value: playlist) {
                        PlaylistRow(playlist: playlist)
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
                                Task { await viewModel.loadMorePlaylists() }
                            }
                        }
                }
            }
        }
        .navigationDestination(for: Playlist.self) { playlist in
            PlaylistDetailView(
                playlistId: playlist.id,
                playlistName: playlist.name,
                musicService: musicService,
                selectedSongIds: $selectedSongIds,
                isAtCapacity: isAtCapacity,
                onToggleSong: onToggleSong
            )
        }
    }

    private var skeletonList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(0..<10, id: \.self) { _ in
                    SkeletonSongRow()
                    Divider().padding(.leading, 72)
                }
            }
        }
    }
}

private struct PlaylistRow: View {
    let playlist: Playlist

    var body: some View {
        HStack(spacing: 12) {
            EntityArtwork(entityId: playlist.id, type: .playlist)

            Text(playlist.name)
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
