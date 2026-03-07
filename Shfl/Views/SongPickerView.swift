import SwiftUI

enum BrowseMode: String, CaseIterable {
    case songs = "Songs"
    case artists = "Artists"
    case playlists = "Playlists"

    var iconName: String {
        switch self {
        case .songs: "music.note"
        case .artists: "music.mic"
        case .playlists: "music.note.list"
        }
    }
}

private enum PickerTab: Hashable {
    case songs, artists, playlists, search
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
    // Local copy of pool IDs — trades possible staleness for isolation from player observation churn
    @State private var selectedSongIds: Set<String> = []
    @State private var searchText = ""
    @State private var searchScope: BrowseMode = .songs
    @State private var activeTab: PickerTab = .songs
    @State private var actionErrorMessage: String?
    @FocusState private var isSearchFieldFocused: Bool

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
        if #available(iOS 26, *) {
            tabViewBody
        } else {
            legacyBody
        }
    }

    // MARK: - iOS 26+ TabView Body

    @available(iOS 26, *)
    private var tabViewBody: some View {
        TabView(selection: $activeTab) {
            Tab("Songs", systemImage: "music.note", value: PickerTab.songs) {
                NavigationStack {
                    pickerNavigationChrome {
                        tabContent(for: .songs)
                    }
                }
            }

            Tab("Artists", systemImage: "music.mic", value: PickerTab.artists) {
                NavigationStack {
                    pickerNavigationChrome {
                        tabContent(for: .artists)
                    }
                }
            }

            Tab("Playlists", systemImage: "music.note.list", value: PickerTab.playlists) {
                NavigationStack {
                    pickerNavigationChrome {
                        tabContent(for: .playlists)
                    }
                }
            }

            Tab("Search", systemImage: "magnifyingglass", value: PickerTab.search) {
                NavigationStack {
                    pickerNavigationChrome {
                        searchTabContent
                    }
                }
            }
        }
        .onChange(of: activeTab) { _, newTab in
            if newTab == .search {
                viewModel.browseMode = searchScope
                if searchText.isEmpty {
                    loadBrowseData(for: searchScope)
                }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(120))
                    guard activeTab == .search else { return }
                    isSearchFieldFocused = true
                }
            } else {
                isSearchFieldFocused = false
                let mode = browseMode(for: newTab)
                viewModel.browseMode = mode
                Task { @MainActor in
                    switch mode {
                    case .songs: await viewModel.loadInitialPage()
                    case .artists: await viewModel.loadInitialArtists()
                    case .playlists: await viewModel.loadInitialPlaylists()
                    }
                }
            }
        }
        .onChange(of: appSettings?.librarySortOption) { _, newOption in
            if let newOption {
                viewModel.handleSortOptionChanged(newOption)
            }
        }
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

    // MARK: - Tab Content

    @ViewBuilder
    private func browseContentFor(_ mode: BrowseMode) -> some View {
        switch mode {
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

    @ViewBuilder
    private func searchContentFor(_ mode: BrowseMode) -> some View {
        switch mode {
        case .songs: songSearchList
        case .artists: artistSearchList
        case .playlists: playlistSearchList
        }
    }

    private func contentShell<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack(alignment: .bottom) {
            content()
            overlayPills
        }
    }

    private func tabContent(for tab: PickerTab) -> some View {
        contentShell {
            browseContentFor(browseMode(for: tab))
        }
    }

    @available(iOS 26, *)
    private func pickerNavigationChrome<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    toolbarCapacityView
                }

                ToolbarItem(placement: .topBarTrailing) {
                    toolbarActionGroup
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color(.systemGroupedBackground), for: .navigationBar)
    }

    @available(iOS 26, *)
    private var toolbarCapacityView: some View {
        CapacityRing(
            current: selectedSongIds.count,
            maximum: player.capacity
        )
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
        .accessibilityLabel("\(selectedSongIds.count) of \(player.capacity) songs selected")
    }

    @available(iOS 26, *)
    private var toolbarActionGroup: some View {
        HStack(spacing: 6) {
            autofillToolbarButton
            clearToolbarButton

            if showSortButton {
                sortToolbarButton
            }
        }
        .padding(.leading, 6)
    }

    private var searchTabContent: some View {
        ZStack(alignment: .bottom) {
            if searchText.isEmpty {
                browseContentFor(searchScope)
            } else {
                searchContentFor(searchScope)
            }
            overlayPills
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            searchScopePicker
            .padding(.top, 6)
            .padding(.bottom, 10)
            .background(
                Color(.systemGroupedBackground)
                    .shadow(.drop(color: .black.opacity(0.08), radius: 3, y: 2))
            )
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            searchFieldDock
        }
    }

    // MARK: - Legacy Body (pre-iOS 26)

    private var legacyBody: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Group {
                    if searchText.isEmpty {
                        legacyBrowseContent
                    } else {
                        legacySearchList
                    }
                }

                overlayPills
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 6) {
                    headerActionRow
                    legacyBrowseModePickerBar
                }
                .padding(.top, 6)
                .padding(.bottom, 10)
                .background(
                    Color(.systemGroupedBackground)
                        .shadow(.drop(color: .black.opacity(0.08), radius: 3, y: 2))
                )
            }
            .searchable(text: $searchText, prompt: "Search your library")
            .task {
                await viewModel.loadInitialPage()
            }
            .onChange(of: searchText) { _, newValue in
                viewModel.searchText = newValue
            }
            .onChange(of: searchScope) { _, newMode in
                viewModel.browseMode = newMode
                Task { @MainActor in
                    switch newMode {
                    case .songs: await viewModel.loadInitialPage()
                    case .artists: await viewModel.loadInitialArtists()
                    case .playlists: await viewModel.loadInitialPlaylists()
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

    private var legacyBrowseModePickerBar: some View {
        Picker("Browse", selection: $searchScope) {
            ForEach(BrowseMode.allCases, id: \.self) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var legacyBrowseContent: some View {
        switch searchScope {
        case .songs: browseList
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

    @ViewBuilder
    private var legacySearchList: some View {
        switch searchScope {
        case .songs: songSearchList
        case .artists: artistSearchList
        case .playlists: playlistSearchList
        }
    }

    // MARK: - Header

    private var headerActionRow: some View {
        HStack(alignment: .center, spacing: 16) {
            CapacityRing(
                current: selectedSongIds.count,
                maximum: player.capacity
            )

            Spacer()

            HStack(spacing: 18) {
                autofillButton
                clearButton

                if showSortButton {
                    sortButton
                }
            }
        }
        .frame(minHeight: 52)
        .padding(.horizontal, 20)
        .padding(.vertical, 2)
    }

    private var searchScopePicker: some View {
        Picker("Browse", selection: $searchScope) {
            ForEach(BrowseMode.allCases, id: \.self) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .onChange(of: searchScope) { _, newScope in
            viewModel.browseMode = newScope
            if searchText.isEmpty {
                loadBrowseData(for: newScope)
            } else {
                viewModel.handleSearchTextChanged()
            }
        }
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

    private var autofillButton: some View {
        Button {
            performAutofill()
        } label: {
            Text("Autofill")
                .font(.system(size: 14, weight: .semibold))
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.small)
        .disabled(isAutofillDisabled)
    }

    @available(iOS 26, *)
    private var autofillToolbarButton: some View {
        Button {
            performAutofill()
        }
        label: {
            Text("Autofill")
                .font(.system(size: 16, weight: .semibold))
        }
        .buttonStyle(.plain)
        .foregroundStyle(isAutofillDisabled ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
        .disabled(isAutofillDisabled)
        .padding(.horizontal, 8)
        .frame(height: 32)
    }

    private var clearButton: some View {
        Button {
            clearSelectedSongs()
        } label: {
            Text("Clear")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(selectedSongIds.isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
        }
        .buttonStyle(.plain)
        .disabled(selectedSongIds.isEmpty)
    }

    @available(iOS 26, *)
    private var clearToolbarButton: some View {
        Button("Clear") {
            clearSelectedSongs()
        }
        .buttonStyle(.plain)
        .font(.system(size: 16, weight: .medium))
        .foregroundStyle(selectedSongIds.isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
        .disabled(selectedSongIds.isEmpty)
        .padding(.horizontal, 8)
        .frame(height: 32)
    }

    @available(iOS 26, *)
    private var sortToolbarButton: some View {
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
                .font(.system(size: 19, weight: .medium))
                .frame(width: 28, height: 32)
                .foregroundStyle(.pink)
        }
        .buttonStyle(.plain)
    }

    private var isAutofillDisabled: Bool {
        selectedSongIds.count >= player.capacity || viewModel.autofillState == .loading
    }

    private var showSortButton: Bool {
        if #available(iOS 26, *) {
            return activeTab == .songs || (activeTab == .search && searchScope == .songs)
        } else {
            return searchScope == .songs
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

    // MARK: - Search Lists

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
        .scrollDismissesKeyboard(.interactively)
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

    private var skeletonList: some View { SkeletonList() }

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
        .padding(.bottom, activeTab == .search ? 96 : 16)
    }

    private var searchFieldDock: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.secondary)

            TextField("Search your library", text: searchTextBinding)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($isSearchFieldFocused)

            if !searchText.isEmpty {
                Button {
                    searchTextBinding.wrappedValue = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .font(.system(size: 17))
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(Color.clear)
    }

    // MARK: - Helpers

    private var searchTextBinding: Binding<String> {
        Binding(
            get: { searchText },
            set: { newValue in
                searchText = newValue
                viewModel.searchText = newValue
                if newValue.isEmpty {
                    loadBrowseData(for: searchScope)
                }
            }
        )
    }

    private func browseMode(for tab: PickerTab) -> BrowseMode {
        switch tab {
        case .songs: .songs
        case .artists: .artists
        case .playlists: .playlists
        case .search: searchScope
        }
    }

    private func pickerTab(for mode: BrowseMode) -> PickerTab {
        switch mode {
        case .songs: .songs
        case .artists: .artists
        case .playlists: .playlists
        }
    }

    private func loadBrowseData(for mode: BrowseMode) {
        Task { @MainActor in
            switch mode {
            case .songs: await viewModel.loadInitialPage()
            case .artists: await viewModel.loadInitialArtists()
            case .playlists: await viewModel.loadInitialPlaylists()
            }
        }
    }

    private func performAutofill() {
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
    }

    private func clearSelectedSongs() {
        Task { @MainActor in await onRemoveAllSongs() }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            selectedSongIds.removeAll()
        }
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

// MARK: - Previews

private final class PreviewPickerMusicService: MusicService {
    static let sampleSongs: [Song] = [
        Song(id: "1", title: "Bohemian Rhapsody", artist: "Queen", albumTitle: "A Night at the Opera", artworkURL: nil, playCount: 142),
        Song(id: "2", title: "Stairway to Heaven", artist: "Led Zeppelin", albumTitle: "Led Zeppelin IV", artworkURL: nil, playCount: 98),
        Song(id: "3", title: "Hotel California", artist: "Eagles", albumTitle: "Hotel California", artworkURL: nil, playCount: 76),
        Song(id: "4", title: "Comfortably Numb", artist: "Pink Floyd", albumTitle: "The Wall", artworkURL: nil, playCount: 63),
        Song(id: "5", title: "Sweet Child O' Mine", artist: "Guns N' Roses", albumTitle: "Appetite for Destruction", artworkURL: nil, playCount: 55),
        Song(id: "6", title: "Wish You Were Here", artist: "Pink Floyd", albumTitle: "Wish You Were Here", artworkURL: nil, playCount: 49),
        Song(id: "7", title: "Back in Black", artist: "AC/DC", albumTitle: "Back in Black", artworkURL: nil, playCount: 41),
        Song(id: "8", title: "Imagine", artist: "John Lennon", albumTitle: "Imagine", artworkURL: nil, playCount: 37),
        Song(id: "9", title: "Hey Jude", artist: "The Beatles", albumTitle: "Hey Jude", artworkURL: nil, playCount: 30),
        Song(id: "10", title: "Smells Like Teen Spirit", artist: "Nirvana", albumTitle: "Nevermind", artworkURL: nil, playCount: 25),
    ]

    static let sampleArtists: [Artist] = [
        Artist(id: "a1", name: "Queen"),
        Artist(id: "a2", name: "Led Zeppelin"),
        Artist(id: "a3", name: "Pink Floyd"),
        Artist(id: "a4", name: "Eagles"),
    ]

    static let samplePlaylists: [Playlist] = [
        Playlist(id: "p1", name: "Classic Rock Hits"),
        Playlist(id: "p2", name: "Road Trip Mix"),
        Playlist(id: "p3", name: "Chill Vibes"),
    ]

    var isAuthorized: Bool { true }
    var currentPlaybackTime: TimeInterval { 0 }
    var currentSongDuration: TimeInterval { 180 }
    var currentSongId: String? { nil }
    var transportQueueEntryCount: Int { 0 }

    var playbackStateStream: AsyncStream<PlaybackState> {
        AsyncStream { $0.yield(.empty) }
    }

    func requestAuthorization() async -> Bool { true }

    func fetchLibrarySongs(sortedBy: SortOption, limit: Int, offset: Int) async throws -> LibraryPage {
        let end = min(offset + limit, Self.sampleSongs.count)
        guard offset < Self.sampleSongs.count else { return LibraryPage(songs: [], hasMore: false) }
        return LibraryPage(songs: Array(Self.sampleSongs[offset..<end]), hasMore: end < Self.sampleSongs.count)
    }

    func searchLibrarySongs(query: String, limit: Int, offset: Int) async throws -> LibraryPage {
        let filtered = Self.sampleSongs.filter { $0.title.localizedCaseInsensitiveContains(query) || $0.artist.localizedCaseInsensitiveContains(query) }
        return LibraryPage(songs: filtered, hasMore: false)
    }

    func searchLibraryArtists(query: String, limit: Int, offset: Int) async throws -> ArtistPage {
        let filtered = Self.sampleArtists.filter { $0.name.localizedCaseInsensitiveContains(query) }
        return ArtistPage(artists: filtered, hasMore: false)
    }

    func searchLibraryPlaylists(query: String, limit: Int, offset: Int) async throws -> PlaylistPage {
        let filtered = Self.samplePlaylists.filter { $0.name.localizedCaseInsensitiveContains(query) }
        return PlaylistPage(playlists: filtered, hasMore: false)
    }

    func fetchLibraryArtists(limit: Int, offset: Int) async throws -> ArtistPage {
        ArtistPage(artists: Self.sampleArtists, hasMore: false)
    }

    func fetchLibraryPlaylists(limit: Int, offset: Int) async throws -> PlaylistPage {
        PlaylistPage(playlists: Self.samplePlaylists, hasMore: false)
    }

    func fetchSongs(byArtist artistName: String, limit: Int, offset: Int) async throws -> LibraryPage {
        let filtered = Self.sampleSongs.filter { $0.artist == artistName }
        return LibraryPage(songs: filtered, hasMore: false)
    }

    func fetchSongs(byPlaylistId playlistId: String, limit: Int, offset: Int) async throws -> LibraryPage {
        LibraryPage(songs: Array(Self.sampleSongs.prefix(3)), hasMore: false)
    }

    func setQueue(songs: [Song]) async throws {}
    func replaceQueue(queue: [Song], startAtSongId: String?, policy: QueueApplyPolicy) async throws {}
    func play() async throws {}
    func pause() async {}
    func pauseImmediately() {}
    func skipToNext() async throws {}
    func skipToPrevious() async throws {}
    func restartOrSkipToPrevious() async throws {}
    func seek(to time: TimeInterval) {}
}

#Preview("Songs Tab") {
    let service = PreviewPickerMusicService()
    let player = ShufflePlayer(musicService: service)

    SongPickerView(
        player: player,
        musicService: service,
        initialSortOption: .mostPlayed,
        onAddSong: { _ in },
        onAddSongsWithQueueRebuild: { _ in },
        onRemoveSong: { _ in },
        onRemoveAllSongs: {},
        onDismiss: {}
    )
    .environment(\.appSettings, AppSettings())
}

#Preview("With Selected Songs") {
    struct Wrapper: View {
        let service = PreviewPickerMusicService()
        @State private var player: ShufflePlayer?

        var body: some View {
            if let player {
                SongPickerView(
                    player: player,
                    musicService: service,
                    initialSortOption: .mostPlayed,
                    onAddSong: { _ in },
                    onAddSongsWithQueueRebuild: { _ in },
                    onRemoveSong: { _ in },
                    onRemoveAllSongs: {},
                    onDismiss: {}
                )
                .environment(\.appSettings, AppSettings())
            } else {
                ProgressView()
                    .task {
                        let p = ShufflePlayer(musicService: service)
                        for song in PreviewPickerMusicService.sampleSongs.prefix(5) {
                            try? await p.addSong(song)
                        }
                        player = p
                    }
            }
        }
    }

    return Wrapper()
}

#Preview("Empty Library") {
    let service = MockMusicService()
    let player = ShufflePlayer(musicService: service)

    SongPickerView(
        player: player,
        musicService: service,
        initialSortOption: .mostPlayed,
        onAddSong: { _ in },
        onAddSongsWithQueueRebuild: { _ in },
        onRemoveSong: { _ in },
        onRemoveAllSongs: {},
        onDismiss: {}
    )
    .environment(\.appSettings, AppSettings())
}
