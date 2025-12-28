import SwiftUI

struct SongPickerView: View {
    @ObservedObject var player: ShufflePlayer
    let musicService: MusicService
    let onDismiss: () -> Void

    @StateObject private var viewModel: LibraryBrowserViewModel
    @StateObject private var undoManager = SongUndoManager()

    init(
        player: ShufflePlayer,
        musicService: MusicService,
        onDismiss: @escaping () -> Void
    ) {
        self.player = player
        self.musicService = musicService
        self.onDismiss = onDismiss
        self._viewModel = StateObject(wrappedValue: LibraryBrowserViewModel(musicService: musicService))
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    CapacityProgressBar(current: player.songCount, maximum: player.capacity)

                    Group {
                        switch viewModel.currentMode {
                        case .browse:
                            browseList
                        case .search:
                            searchList
                        }
                    }
                }

                if let undoState = undoManager.currentState {
                    UndoPill(
                        state: undoState,
                        onUndo: { handleUndo(undoState) },
                        onDismiss: { undoManager.dismiss() }
                    )
                    .padding(.bottom, 32)
                }

                if showAutofillBanner {
                    Text(autofillMessage)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 32)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .onAppear {
                            Task {
                                try? await Task.sleep(for: .seconds(2))
                                withAnimation {
                                    viewModel.resetAutofillState()
                                }
                            }
                        }
                }
            }
            .navigationTitle("Add Songs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if viewModel.autofillState == .loading {
                        ProgressView()
                            .progressViewStyle(.circular)
                    } else {
                        Button("Autofill") {
                            Task {
                                let source = LibraryAutofillSource(musicService: musicService)
                                await viewModel.autofill(into: player, using: source)
                            }
                        }
                        .disabled(player.remainingCapacity == 0)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Clear") {
                        player.removeAllSongs()
                    }
                    .disabled(player.songCount == 0)
                }
            }
            .searchable(text: $viewModel.searchText, prompt: "Search your library")
            .task {
                await viewModel.loadInitialPage()
            }
            .alert("Error", isPresented: .init(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.clearError() } }
            )) {
                Button("OK") { viewModel.clearError() }
            } message: {
                if let error = viewModel.errorMessage {
                    Text(error)
                }
            }
        }
    }

    @ViewBuilder
    private var browseList: some View {
        if viewModel.browseLoading && viewModel.browseSongs.isEmpty {
            skeletonList
        } else if viewModel.browseSongs.isEmpty {
            ContentUnavailableView(
                "No Songs in Library",
                systemImage: "music.note",
                description: Text("Add songs to your Apple Music library to see them here")
            )
        } else {
            songList(songs: viewModel.browseSongs, isPaginated: true)
        }
    }

    @ViewBuilder
    private var searchList: some View {
        if viewModel.searchLoading {
            skeletonList
        } else if viewModel.searchResults.isEmpty && !viewModel.searchText.isEmpty {
            ContentUnavailableView.search(text: viewModel.searchText)
        } else if viewModel.searchResults.isEmpty {
            ContentUnavailableView(
                "Search Your Library",
                systemImage: "magnifyingglass",
                description: Text("Type to search your Apple Music library")
            )
        } else {
            songList(songs: viewModel.searchResults, isPaginated: false)
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

    private func songList(songs: [Song], isPaginated: Bool) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(songs) { song in
                    SongRow(
                        song: song,
                        isSelected: player.containsSong(id: song.id),
                        isAtCapacity: player.remainingCapacity == 0,
                        onToggle: { toggleSong(song) }
                    )
                    .onAppear {
                        if isPaginated {
                            Task {
                                await viewModel.loadNextPageIfNeeded(currentSong: song)
                            }
                        }
                    }
                    Divider().padding(.leading, 72)
                }

                if isPaginated && viewModel.hasMorePages {
                    ProgressView()
                        .padding()
                }
            }
        }
    }

    private func toggleSong(_ song: Song) {
        if player.containsSong(id: song.id) {
            player.removeSong(id: song.id)
            undoManager.recordAction(.removed, song: song)
        } else {
            do {
                try player.addSong(song)
                undoManager.recordAction(.added, song: song)

                if CapacityProgressBar.isMilestone(player.songCount) {
                    HapticFeedback.milestone.trigger()
                }
            } catch ShufflePlayerError.capacityReached {
                // Handled by SongRow's nope animation
            } catch {
                // Other errors handled by alert
            }
        }
    }

    private func handleUndo(_ state: UndoState) {
        switch state.action {
        case .added:
            player.removeSong(id: state.song.id)
            HapticFeedback.light.trigger()
        case .removed:
            try? player.addSong(state.song)
            HapticFeedback.medium.trigger()
        }
        undoManager.dismiss()
    }

    private var showAutofillBanner: Bool {
        if case .completed = viewModel.autofillState {
            return true
        }
        return false
    }

    private var autofillMessage: String {
        if case .completed(let count) = viewModel.autofillState {
            return "Added \(count) songs"
        }
        return ""
    }
}
