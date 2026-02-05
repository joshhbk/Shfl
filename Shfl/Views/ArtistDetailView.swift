import SwiftUI

struct ArtistDetailView: View {
    @State private var viewModel: ArtistDetailViewModel
    @Binding var selectedSongIds: Set<String>
    let isAtCapacity: Bool
    let onToggleSong: (Song) -> Void

    init(
        artistName: String,
        musicService: MusicService,
        selectedSongIds: Binding<Set<String>>,
        isAtCapacity: Bool,
        onToggleSong: @escaping (Song) -> Void
    ) {
        self._viewModel = State(wrappedValue: ArtistDetailViewModel(
            artistName: artistName,
            musicService: musicService
        ))
        self._selectedSongIds = selectedSongIds
        self.isAtCapacity = isAtCapacity
        self.onToggleSong = onToggleSong
    }

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.songs.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.songs.isEmpty {
                ContentUnavailableView(
                    "No Songs Found",
                    systemImage: "music.note",
                    description: Text("No songs by this artist in your library")
                )
            } else {
                songList
            }
        }
        .navigationTitle(viewModel.artistName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadInitialPage()
        }
    }

    private var songList: some View {
        ScrollView {
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
}
