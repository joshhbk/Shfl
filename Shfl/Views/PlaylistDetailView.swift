import SwiftUI

struct PlaylistDetailView: View {
    @State private var viewModel: PlaylistDetailViewModel
    @Binding var selectedSongIds: Set<String>
    let isAtCapacity: Bool
    let onToggleSong: (Song) -> Void

    init(
        playlistId: String,
        playlistName: String,
        musicService: MusicService,
        selectedSongIds: Binding<Set<String>>,
        isAtCapacity: Bool,
        onToggleSong: @escaping (Song) -> Void
    ) {
        self._viewModel = State(wrappedValue: PlaylistDetailViewModel(
            playlistId: playlistId,
            playlistName: playlistName,
            musicService: musicService
        ))
        self._selectedSongIds = selectedSongIds
        self.isAtCapacity = isAtCapacity
        self.onToggleSong = onToggleSong
    }

    var body: some View {
        content
        .navigationTitle(viewModel.playlistName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(Color(.systemGroupedBackground), for: .navigationBar)
        .task {
            await viewModel.loadInitialPage()
        }
    }

    private var content: some View {
        ScrollView {
            Group {
                if viewModel.isLoading && viewModel.songs.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 48)
                } else if viewModel.songs.isEmpty {
                    ContentUnavailableView(
                        "No Songs Found",
                        systemImage: "music.note",
                        description: Text("No songs in this playlist")
                    )
                    .padding(.top, 24)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.songs) { song in
                            SongRow(
                                song: song,
                                isSelected: selectedSongIds.contains(song.id),
                                isAtCapacity: isAtCapacity,
                                onToggle: { onToggleSong(song) }
                            )
                            .equatable()
                            Divider().padding(.leading, 72)
                        }

                        if viewModel.hasMorePages {
                            ProgressView()
                                .padding()
                                .onAppear {
                                    Task { await viewModel.loadMorePages() }
                                }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}
