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
    @State private var actionErrorMessage: String?
    @State private var navigationPath = NavigationPath()
    @State private var autofillIsExhausted = false
    @State private var showingAutofillCompletion = false
    @State private var autofillTapCount = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isSearchFieldFocused: Bool

    @Environment(\.appSettings) private var appSettings
    @Environment(\.shuffleTheme) private var shuffleTheme

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
                libraryCatalog: musicService,
                initialSortOption: initialSortOption
            )
        )
        self._selectedSongIds = State(wrappedValue: Set(player.allSongs.map(\.id)))
    }

    var body: some View {
        Group {
            if #available(iOS 26, *) {
                modernBody
            } else {
                legacyBody
            }
        }

    }

    // MARK: - iOS 26+ Picker

    @available(iOS 26, *)
    private var modernBody: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if searchText.isEmpty {
                    browseContentFor(searchScope)
                } else {
                    searchContentFor(searchScope)
                }
            }
            .accessibilityHidden(!navigationPath.isEmpty)
            .navigationTitle("Pick Your Songs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if showSortButton {
                        modernSortMenu(style: .systemDefault)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", action: onDismiss)
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("songPicker.close")
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                modernDiscoveryHeader
                    .accessibilityHidden(!navigationPath.isEmpty)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                overlayPills

                if !isSearchFieldFocused && searchText.isEmpty {
                    modernCompletionBar
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilitySortPriority(-1)
        }
        .onChange(of: searchScope) { _, newMode in
            viewModel.browseMode = newMode
            if searchText.isEmpty {
                loadBrowseData(for: newMode)
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
        .tint(pickerAccentColor)
    }

    @available(iOS 26, *)
    private var modernDiscoveryHeader: some View {
        let style = PickerHeaderStyle.systemDefault

        return VStack(alignment: .leading, spacing: 12) {
            modernSearchField

            HStack(spacing: 10) {
                Picker("Browse", selection: $searchScope) {
                    ForEach(BrowseMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("songPicker.scope")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background {
            style.background
                .ignoresSafeArea(.container, edges: .top)
        }
    }

    @available(iOS 26, *)
    private var modernSearchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search your library", text: searchTextBinding)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($isSearchFieldFocused)
                .accessibilityIdentifier("songPicker.search")

            if !searchText.isEmpty {
                Button {
                    searchTextBinding.wrappedValue = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .font(.body)
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 12)
        )
    }

    @available(iOS 26, *)
    private func modernSortMenu(style: PickerHeaderStyle) -> some View {
        Menu {
            Picker("Sort", selection: sortSelection) {
                ForEach(SortOption.allCases, id: \.self) { option in
                    Text(option.displayName).tag(option)
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .foregroundStyle(style.primaryContent)
                .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel("Sort songs")
        .accessibilityValue(currentSortOption.displayName)
        .accessibilityIdentifier("songPicker.sort")
    }

    @available(iOS 26, *)
    private var modernCompletionBar: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                if shouldOfferAutofill || showingAutofillCompletion {
                    Button(action: performAutofill) {
                        HStack(spacing: 6) {
                            if viewModel.autofillState == .loading {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: showingAutofillCompletion ? "checkmark" : "shuffle")
                                    .contentTransition(.symbolEffect(.replace))
                                    .symbolEffect(.bounce, options: .nonRepeating, value: reduceMotion ? 0 : autofillTapCount)
                            }
                            Text(showingAutofillCompletion ? "Ready" : "Autofill")
                                .font(.subheadline.weight(.semibold))
                        }
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .foregroundStyle(pickerAccentColor)
                        .glassEffect(
                            .regular.tint(shuffleTheme.accentColor.opacity(0.25)).interactive(),
                            in: .capsule
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.autofillState == .loading || showingAutofillCompletion)
                    .task(id: showingAutofillCompletion) {
                        guard showingAutofillCompletion else { return }
                        do {
                            try await Task.sleep(for: .milliseconds(900))
                        } catch { return }
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                            showingAutofillCompletion = false
                        }
                    }
                    .accessibilityHint(completionActionHint)
                    .accessibilityIdentifier("songPicker.autofill")
                }

                if !selectedSongIds.isEmpty {
                    Button(role: .destructive, action: clearSelectedSongs) {
                        Image(systemName: "trash")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(pickerAccentColor)
                            .frame(width: 44, height: 44)
                            .glassEffect(.regular.interactive(), in: .circle)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear All")
                    .accessibilityHint("Removes all picked songs")
                    .accessibilityIdentifier("songPicker.clear")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var pickerAccentColor: Color {
        shuffleTheme.interactionColor
    }

    private var currentSortOption: SortOption {
        appSettings?.librarySortOption ?? .mostPlayed
    }

    private var sortSelection: Binding<SortOption> {
        Binding(
            get: { currentSortOption },
            set: { appSettings?.librarySortOption = $0 }
        )
    }

    private var remainingCapacity: Int {
        max(player.capacity - selectedSongIds.count, 0)
    }

    private var shouldOfferAutofill: Bool {
        remainingCapacity > 0 && !autofillIsExhausted
    }

    private var completionActionHint: String {
        "Adds available songs up to \(player.capacity) total"
    }

    // MARK: - Library Content

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

    private var isAutofillDisabled: Bool {
        selectedSongIds.count >= player.capacity || viewModel.autofillState == .loading
    }

    private var showSortButton: Bool {
        searchScope == .songs && searchText.isEmpty
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
        if hasOverlayMessage {
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
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private var hasOverlayMessage: Bool {
        undoManager.currentState != nil || actionErrorMessage != nil || showAutofillBanner
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
        autofillTapCount += 1
        HapticFeedback.light.trigger()
        Task { @MainActor in
            let requestedCount = remainingCapacity
            let algorithm = appSettings?.autofillAlgorithm ?? .random
            let source = LibraryAutofillSource(libraryCatalog: musicService, algorithm: algorithm)
            await viewModel.autofill(
                into: player,
                using: source,
                addSongs: { songs in
                    try await onAddSongsWithQueueRebuild(songs)
                }
            )
            let updatedSongIds = Set(player.allSongs.map(\.id))
            selectedSongIds = updatedSongIds

            if case .completed(let count) = viewModel.autofillState {
                showingAutofillCompletion = count > 0
                autofillIsExhausted = count < requestedCount && updatedSongIds.count < player.capacity
            }
        }
    }

    private func clearSelectedSongs() {
        showingAutofillCompletion = false
        autofillIsExhausted = false
        undoManager.dismiss()
        Task { @MainActor in await onRemoveAllSongs() }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            selectedSongIds.removeAll()
        }
    }

    // MARK: - Actions

    private func toggleSong(_ song: Song) {
        autofillIsExhausted = false

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
        autofillIsExhausted = false

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
        case .completed(let count):
            return count > 0
        case .error:
            return true
        case .idle, .loading:
            return false
        }
    }

    private var autofillMessage: String {
        if case .completed(let count) = viewModel.autofillState {
            let noun = count == 1 ? "song" : "songs"
            return "Added \(count) \(noun)"
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

private enum PreviewPickerLibrary {
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

    static let samplePlaylists: [Playlist] = [
        Playlist(id: "p1", name: "Classic Rock Hits"),
        Playlist(id: "p2", name: "Road Trip Mix"),
        Playlist(id: "p3", name: "Chill Vibes"),
    ]

    static func makeService() -> DeterministicMusicService {
        DeterministicMusicService(
            configuration: .init(
                librarySongs: sampleSongs,
                libraryPlaylists: samplePlaylists,
                playlistSongs: [
                    "p1": Array(sampleSongs.prefix(3)),
                    "p2": Array(sampleSongs.dropFirst(3).prefix(3)),
                    "p3": Array(sampleSongs.dropFirst(6).prefix(3))
                ]
            )
        )
    }
}

#Preview("Songs Tab") {
    let service = PreviewPickerLibrary.makeService()
    let player = ShufflePlayer(playbackTransport: service)

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
        let service = PreviewPickerLibrary.makeService()
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
                        let p = ShufflePlayer(playbackTransport: service)
                        for song in PreviewPickerLibrary.sampleSongs.prefix(5) {
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
    let service = DeterministicMusicService()
    let player = ShufflePlayer(playbackTransport: service)

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
