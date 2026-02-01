import SwiftUI

struct SongPickerView: View {
    var player: ShufflePlayer
    let musicService: MusicService
    let onDismiss: () -> Void

    @State private var viewModel: LibraryBrowserViewModel
    @State private var undoManager = SongUndoManager()
    @State private var selectedSongIds: Set<String> = []

    @Environment(\.appSettings) private var appSettings

    init(
        player: ShufflePlayer,
        musicService: MusicService,
        onDismiss: @escaping () -> Void
    ) {
        self.player = player
        self.musicService = musicService
        self.onDismiss = onDismiss
        self._viewModel = State(wrappedValue: LibraryBrowserViewModel(musicService: musicService))
        self._selectedSongIds = State(wrappedValue: Set(player.allSongs.map(\.id)))
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    CapacityProgressBar(current: selectedSongIds.count, maximum: player.capacity)

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
                            print("🔍 AUTOFILL BUTTON TAPPED")
                            Task {
                                print("🔍 AUTOFILL TASK STARTED")
                                let algorithmRaw = UserDefaults.standard.string(forKey: "autofillAlgorithm") ?? "random"
                                let algorithm = AutofillAlgorithm(rawValue: algorithmRaw) ?? .random
                                let source = LibraryAutofillSource(musicService: musicService, algorithm: algorithm)
                                print("🔍 AUTOFILL CALLING viewModel.autofill...")
                                await viewModel.autofill(into: player, using: source)
                                print("🔍 AUTOFILL viewModel.autofill RETURNED")
                                // Sync cached IDs after autofill
                                selectedSongIds = Set(player.allSongs.map(\.id))
                            }
                        }
                        .disabled(selectedSongIds.count >= player.capacity)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Clear") {
                        player.removeAllSongs()
                        selectedSongIds.removeAll()
                    }
                    .disabled(selectedSongIds.isEmpty)
                }
            }
            .searchable(text: Bindable(viewModel).searchText, prompt: "Search your library")
            .task {
                await viewModel.loadInitialPage()
            }
            .onChange(of: appSettings?.librarySortOption) { _, newOption in
                if let newOption {
                    viewModel.handleSortOptionChanged(newOption)
                }
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
        let isAtCapacity = selectedSongIds.count >= player.capacity

        return ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(songs) { song in
                    SongRow(
                        song: song,
                        isSelected: selectedSongIds.contains(song.id),
                        isAtCapacity: isAtCapacity,
                        onToggle: { toggleSong(song) }
                    )
                    Divider().padding(.leading, 72)
                }

                if isPaginated && viewModel.hasMorePages {
                    ProgressView()
                        .padding()
                        .onAppear {
                            Task {
                                await viewModel.loadMorePages()
                            }
                        }
                }
            }
        }
    }

    private func toggleSong(_ song: Song) {
        if selectedSongIds.contains(song.id) {
            player.removeSong(id: song.id)
            selectedSongIds.remove(song.id)
            undoManager.recordAction(.removed, song: song)
        } else {
            do {
                try player.addSong(song)
                selectedSongIds.insert(song.id)
                undoManager.recordAction(.added, song: song)

                if CapacityProgressBar.isMilestone(selectedSongIds.count) {
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
            selectedSongIds.remove(state.song.id)
            HapticFeedback.light.trigger()
        case .removed:
            try? player.addSong(state.song)
            selectedSongIds.insert(state.song.id)
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
