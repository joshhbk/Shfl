import SwiftUI

enum BrowseMode: String, CaseIterable {
    case songs = "Songs"
    case artists = "Artists"
    case playlists = "Playlists"
}

struct SongPickerView: View {
    var player: ShufflePlayer
    let musicService: MusicService
    let onAddSong: @MainActor (Song) async throws -> Void
    let onAddSongsWithQueueRebuild: @MainActor ([Song]) async throws -> Void
    let onRemoveSong: @MainActor (String) async -> Void
    let onRemoveAllSongs: @MainActor () async -> Void
    let onDismiss: () -> Void

    @State private var viewModel: LibraryBrowserViewModel
    @State private var undoManager = SongUndoManager()
    @State private var selectedSongIds: Set<String> = []
    @State private var searchText = ""
    @State private var browseMode: BrowseMode = .songs
    @State private var actionErrorMessage: String?

    @Environment(\.appSettings) private var appSettings

    init(
        player: ShufflePlayer,
        musicService: MusicService,
        initialSortOption: SortOption,
        onAddSong: @escaping @MainActor (Song) async throws -> Void,
        onAddSongsWithQueueRebuild: @escaping @MainActor ([Song]) async throws -> Void,
        onRemoveSong: @escaping @MainActor (String) async -> Void,
        onRemoveAllSongs: @escaping @MainActor () async -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.player = player
        self.musicService = musicService
        self.onAddSong = onAddSong
        self.onAddSongsWithQueueRebuild = onAddSongsWithQueueRebuild
        self.onRemoveSong = onRemoveSong
        self.onRemoveAllSongs = onRemoveAllSongs
        self.onDismiss = onDismiss
        self._viewModel = State(
            wrappedValue: LibraryBrowserViewModel(
                musicService: musicService,
                initialSortOption: initialSortOption
            )
        )
        self._selectedSongIds = State(wrappedValue: Set(player.allSongs.map(\.id)))
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Group {
                    if searchText.isEmpty {
                        browseContent
                    } else {
                        searchList
                    }
                }

                overlayPills
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    headerActionRow
                    headerDivider
                    browseModePickerBar
                }
                .padding(.bottom, 4)
                .background(
                    Color(.systemGroupedBackground)
                        .shadow(.drop(color: .black.opacity(0.25), radius: 6, y: 4))
                )
            }
            .navigationTitle("Add Songs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if browseMode == .songs {
                    ToolbarItem(placement: .topBarTrailing) {
                        sortButton
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search your library")
            .task {
                await viewModel.loadInitialPage()
            }
            .onChange(of: searchText) { _, newValue in
                viewModel.searchText = newValue
            }
            .onChange(of: browseMode) { _, newMode in
                viewModel.browseMode = newMode
                Task { @MainActor in
                    switch newMode {
                    case .songs:
                        await viewModel.loadInitialPage()
                    case .artists:
                        await viewModel.loadInitialArtists()
                    case .playlists:
                        await viewModel.loadInitialPlaylists()
                    }
                }
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

    // MARK: - Header

    private var headerActionRow: some View {
        HStack(spacing: 12) {
            CompactCapacityBar(current: selectedSongIds.count, maximum: player.capacity)

            Spacer(minLength: 8)

            autofillClearGroup
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var headerDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.06))
            .frame(height: 0.5)
            .padding(.horizontal, 16)
    }

    private var browseModePickerBar: some View {
        Picker("Browse", selection: $browseMode) {
            ForEach(BrowseMode.allCases, id: \.self) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var sortButton: some View {
        Menu {
            Picker("Sort", selection: Binding(
                get: { appSettings?.librarySortOption ?? .mostPlayed },
                set: { appSettings?.librarySortOption = $0 }
            )) {
                ForEach(SortOption.allCases, id: \.self) { option in
                    Text(option.displayName).tag(option)
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
    }

    private var autofillClearGroup: some View {
        HStack(spacing: 0) {
            Button {
                Task { @MainActor in
                    let algorithm = appSettings?.autofillAlgorithm ?? .random
                    let source = LibraryAutofillSource(musicService: musicService, algorithm: algorithm)
                    await viewModel.autofill(
                        into: player,
                        using: source,
                        addSongs: { songs in
                            try await onAddSongsWithQueueRebuild(songs)
                        }
                    )
                    selectedSongIds = Set(player.allSongs.map(\.id))
                }
            } label: {
                Text("Autofill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isAutofillDisabled ? .white.opacity(0.3) : .white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
            }
            .disabled(isAutofillDisabled)

            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(width: 0.5, height: 20)

            Button {
                Task { @MainActor in await onRemoveAllSongs() }
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    selectedSongIds.removeAll()
                }
            } label: {
                Text("Clear")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(selectedSongIds.isEmpty ? .white.opacity(0.3) : .red.opacity(0.9))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
            }
            .disabled(selectedSongIds.isEmpty)
        }
        .buttonStyle(.plain)
        .background(Color.white.opacity(0.08), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5))
    }

    private var isAutofillDisabled: Bool {
        selectedSongIds.count >= player.capacity || viewModel.autofillState == .loading
    }

    // MARK: - Browse Content

    @ViewBuilder
    private var browseContent: some View {
        switch browseMode {
        case .songs:
            browseList
        case .artists:
            ArtistListView(
                viewModel: viewModel,
                musicService: musicService,
                selectedSongIds: $selectedSongIds,
                isAtCapacity: selectedSongIds.count >= player.capacity,
                onToggleSong: { toggleSong($0) }
            )
        case .playlists:
            PlaylistListView(
                viewModel: viewModel,
                musicService: musicService,
                selectedSongIds: $selectedSongIds,
                isAtCapacity: selectedSongIds.count >= player.capacity,
                onToggleSong: { toggleSong($0) }
            )
        }
    }

    // MARK: - Song Browse List

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

    // MARK: - Search

    @ViewBuilder
    private var searchList: some View {
        switch browseMode {
        case .songs:
            songSearchList
        case .artists:
            artistSearchList
        case .playlists:
            playlistSearchList
        }
    }

    @ViewBuilder
    private var songSearchList: some View {
        if !viewModel.searchResults.isEmpty {
            songSearchResultsList
        } else if viewModel.searchLoading || !viewModel.hasSearchedOnce {
            skeletonList
        } else {
            ContentUnavailableView.search(text: searchText)
        }
    }

    private var songSearchResultsList: some View {
        let isAtCapacity = selectedSongIds.count >= player.capacity

        return ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.searchResults) { song in
                    SongRow(
                        song: song,
                        isSelected: selectedSongIds.contains(song.id),
                        isAtCapacity: isAtCapacity,
                        onToggle: { toggleSong(song) }
                    )
                    .equatable()
                    Divider().padding(.leading, 72)
                }

                if viewModel.hasMoreSearchResults {
                    ProgressView()
                        .padding()
                        .onAppear {
                            Task { @MainActor in
                                await viewModel.loadMoreSearchResults()
                            }
                        }
                }
            }
        }
    }

    @ViewBuilder
    private var artistSearchList: some View {
        if !viewModel.artistSearchResults.isEmpty {
            artistSearchResultsList
        } else if viewModel.artistSearchLoading || !viewModel.hasArtistSearchedOnce {
            skeletonList
        } else {
            ContentUnavailableView.search(text: searchText)
        }
    }

    private var artistSearchResultsList: some View {
        ArtistListView(
            viewModel: viewModel,
            musicService: musicService,
            selectedSongIds: $selectedSongIds,
            isAtCapacity: selectedSongIds.count >= player.capacity,
            onToggleSong: { toggleSong($0) },
            searchResults: viewModel.artistSearchResults,
            hasMoreSearchResults: viewModel.hasMoreArtistSearchResults,
            onLoadMore: { Task { @MainActor in await viewModel.loadMoreArtistSearchResults() } }
        )
    }

    @ViewBuilder
    private var playlistSearchList: some View {
        if !viewModel.playlistSearchResults.isEmpty {
            playlistSearchResultsList
        } else if viewModel.playlistSearchLoading || !viewModel.hasPlaylistSearchedOnce {
            skeletonList
        } else {
            ContentUnavailableView.search(text: searchText)
        }
    }

    private var playlistSearchResultsList: some View {
        PlaylistListView(
            viewModel: viewModel,
            musicService: musicService,
            selectedSongIds: $selectedSongIds,
            isAtCapacity: selectedSongIds.count >= player.capacity,
            onToggleSong: { toggleSong($0) },
            searchResults: viewModel.playlistSearchResults,
            hasMoreSearchResults: viewModel.hasMorePlaylistSearchResults,
            onLoadMore: { Task { @MainActor in await viewModel.loadMorePlaylistSearchResults() } }
        )
    }

    // MARK: - Shared Components

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
                    .equatable()
                    Divider().padding(.leading, 72)
                }

                if isPaginated && viewModel.hasMorePages {
                    ProgressView()
                        .padding()
                        .onAppear {
                            Task { @MainActor in
                                await viewModel.loadMorePages()
                            }
                        }
                }
            }
        }
    }

    // MARK: - Overlay Pills

    @ViewBuilder
    private var overlayPills: some View {
        VStack(spacing: 8) {
            if let undoState = undoManager.currentState {
                UndoPill(
                    state: undoState,
                    onUndo: { handleUndo(undoState) },
                    onDismiss: { undoManager.dismiss() }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if let actionErrorMessage {
                Text(actionErrorMessage)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.red.opacity(0.9), in: Capsule())
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if showAutofillBanner {
                Text(autofillMessage)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(autofillMessageIsError ? .white : .primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(autofillMessageIsError ? AnyShapeStyle(Color.red.opacity(0.9)) : AnyShapeStyle(.ultraThinMaterial), in: Capsule())
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onAppear {
                        Task { @MainActor in
                            try? await Task.sleep(for: .seconds(2))
                            withAnimation {
                                viewModel.resetAutofillState()
                            }
                        }
                    }
            }
        }
        .padding(.bottom, 16)
    }

    // MARK: - Actions

    private func toggleSong(_ song: Song) {
        if selectedSongIds.contains(song.id) {
            Task { @MainActor in await onRemoveSong(song.id) }
            selectedSongIds.remove(song.id)
            undoManager.recordAction(.removed, song: song)
        } else {
            Task { @MainActor in
                do {
                    try await onAddSong(song)
                    selectedSongIds.insert(song.id)
                    undoManager.recordAction(.added, song: song)

                    if CapacityProgressBar.isMilestone(selectedSongIds.count) {
                        HapticFeedback.milestone.trigger()
                    }
                } catch ShufflePlayerError.capacityReached {
                    // Handled by SongRow's nope animation
                } catch {
                    showActionError(error.localizedDescription)
                }
            }
        }
    }

    private func handleUndo(_ state: UndoState) {
        switch state.action {
        case .added:
            Task { @MainActor in await onRemoveSong(state.song.id) }
            selectedSongIds.remove(state.song.id)
            HapticFeedback.light.trigger()
        case .removed:
            Task { @MainActor in
                try? await onAddSong(state.song)
                selectedSongIds.insert(state.song.id)
                HapticFeedback.medium.trigger()
            }
        }
        undoManager.dismiss()
    }

    private var showAutofillBanner: Bool {
        switch viewModel.autofillState {
        case .completed, .error:
            return true
        case .idle, .loading:
            return false
        }
    }

    private var autofillMessage: String {
        if case .completed(let count) = viewModel.autofillState {
            return "Added \(count) songs"
        }
        if case .error(let message) = viewModel.autofillState {
            return message
        }
        return ""
    }

    private var autofillMessageIsError: Bool {
        if case .error = viewModel.autofillState {
            return true
        }
        return false
    }

    private func showActionError(_ message: String) {
        withAnimation {
            actionErrorMessage = message
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            withAnimation {
                if actionErrorMessage == message {
                    actionErrorMessage = nil
                }
            }
        }
    }
}
