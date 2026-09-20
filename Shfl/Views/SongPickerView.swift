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
    let onDismiss: () -> Void

    @State private var viewModel: LibraryBrowserViewModel
    @State private var editor: SessionDraftEditor
    @State private var navigationPath = NavigationPath()
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
        onAddSongs: @escaping @MainActor ([Song]) async throws -> Void,
        onRemoveSong: @escaping @MainActor (String) async -> Void,
        onRemoveAllSongs: @escaping @MainActor () async -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.player = player
        self.musicService = musicService
        self.onDismiss = onDismiss
        self._viewModel = State(
            wrappedValue: LibraryBrowserViewModel(
                libraryCatalog: musicService,
                initialSortOption: initialSortOption
            )
        )
        self._editor = State(
            wrappedValue: SessionDraftEditor(
                player: player,
                addSongs: onAddSongs,
                removeSong: onRemoveSong,
                removeAllSongs: onRemoveAllSongs
            )
        )
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if viewModel.searchText.isEmpty {
                    browseContentFor(viewModel.browseMode)
                } else {
                    searchContentFor(viewModel.browseMode)
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

                if !isSearchFieldFocused && viewModel.searchText.isEmpty {
                    modernCompletionBar
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilitySortPriority(-1)
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

    private var modernDiscoveryHeader: some View {
        let style = PickerHeaderStyle.systemDefault

        return VStack(alignment: .leading, spacing: 12) {
            modernSearchField

            HStack(spacing: 10) {
                Picker("Browse", selection: $viewModel.browseMode) {
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

    private var modernSearchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search your library", text: $viewModel.searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($isSearchFieldFocused)
                .accessibilityIdentifier("songPicker.search")

            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.searchText = ""
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

                if !editor.selectedSongIds.isEmpty {
                    Button(role: .destructive) {
                        showingAutofillCompletion = false
                        editor.clearAll()
                    } label: {
                        Image(systemName: "trash")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(pickerAccentColor)
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
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

    private var shouldOfferAutofill: Bool {
        editor.remainingCapacity > 0 && !editor.autofillIsExhausted
    }

    private var completionActionHint: String {
        "Adds available songs up to \(editor.capacity) total"
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
                selectedSongIds: editor.selectedSongIds,
                isAtCapacity: editor.isAtCapacity,
                onToggleSong: { editor.toggle($0) }
            )
        case .playlists:
            PlaylistListView(
                viewModel: viewModel,
                musicService: musicService,
                selectedSongIds: editor.selectedSongIds,
                isAtCapacity: editor.isAtCapacity,
                onToggleSong: { editor.toggle($0) }
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

    // MARK: - Sort

    private var showSortButton: Bool {
        viewModel.browseMode == .songs && viewModel.searchText.isEmpty
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
            ContentUnavailableView.search(text: viewModel.searchText)
        }
    }

    private var songSearchResultsList: some View {
        let selectedSongIds = editor.selectedSongIds
        let isAtCapacity = editor.isAtCapacity

        return ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.searchResults) { song in
                    SongRow(
                        song: song,
                        isSelected: selectedSongIds.contains(song.id),
                        isAtCapacity: isAtCapacity,
                        onToggle: { editor.toggle(song) }
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
            ContentUnavailableView.search(text: viewModel.searchText)
        }
    }

    private var artistSearchResultsList: some View {
        ArtistListView(
            viewModel: viewModel,
            musicService: musicService,
            selectedSongIds: editor.selectedSongIds,
            isAtCapacity: editor.isAtCapacity,
            onToggleSong: { editor.toggle($0) },
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
            ContentUnavailableView.search(text: viewModel.searchText)
        }
    }

    private var playlistSearchResultsList: some View {
        PlaylistListView(
            viewModel: viewModel,
            musicService: musicService,
            selectedSongIds: editor.selectedSongIds,
            isAtCapacity: editor.isAtCapacity,
            onToggleSong: { editor.toggle($0) },
            searchResults: viewModel.playlistSearchResults,
            hasMoreSearchResults: viewModel.hasMorePlaylistSearchResults,
            onLoadMore: { Task { @MainActor in await viewModel.loadMorePlaylistSearchResults() } }
        )
    }

    // MARK: - Shared Components

    private var skeletonList: some View { SkeletonList() }

    private func songList(songs: [Song], isPaginated: Bool) -> some View {
        let selectedSongIds = editor.selectedSongIds
        let isAtCapacity = editor.isAtCapacity

        return ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(songs) { song in
                    SongRow(
                        song: song,
                        isSelected: selectedSongIds.contains(song.id),
                        isAtCapacity: isAtCapacity,
                        onToggle: { editor.toggle(song) }
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
                if let undoState = editor.undoState {
                    UndoPill(
                        state: undoState,
                        onUndo: { editor.undo(undoState) },
                        onDismiss: { editor.dismissUndo() }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if let actionErrorMessage = editor.actionErrorMessage {
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
        editor.undoState != nil || editor.actionErrorMessage != nil || showAutofillBanner
    }

    // MARK: - Helpers

    private func performAutofill() {
        autofillTapCount += 1
        HapticFeedback.light.trigger()
        Task { @MainActor in
            let requestedCount = editor.remainingCapacity
            let algorithm = appSettings?.autofillAlgorithm ?? .random
            let source = LibraryAutofillSource(libraryCatalog: musicService, algorithm: algorithm)
            await viewModel.autofill(
                into: player,
                using: source,
                addSongs: { songs in
                    try await editor.add(songs)
                }
            )

            if case .completed(let count) = viewModel.autofillState {
                showingAutofillCompletion = count > 0
                editor.noteAutofillCompleted(addedCount: count, requestedCount: requestedCount)
            }
        }
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
        onAddSongs: { _ in },
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
                    onAddSongs: { _ in },
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
        onAddSongs: { _ in },
        onRemoveSong: { _ in },
        onRemoveAllSongs: {},
        onDismiss: {}
    )
    .environment(\.appSettings, AppSettings())
}
