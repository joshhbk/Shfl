import SwiftUI

enum BrowseMode: String, CaseIterable {
    case songs = "Songs"
    case artists = "Artists"
    case playlists = "Playlists"
    case selected = "Selected"

    var iconName: String {
        switch self {
        case .songs: "music.note"
        case .artists: "music.mic"
        case .playlists: "music.note.list"
        case .selected: "checkmark.circle"
        }
    }

    /// The catalog lane this tab browses; the picks aren't a catalog lane.
    var laneKind: LibraryLaneKind? {
        switch self {
        case .songs: .songs
        case .artists: .artists
        case .playlists: .playlists
        case .selected: nil
        }
    }
}

struct SongPickerView: View {
    let libraryCatalog: LibraryCatalog
    let onDismiss: () -> Void

    @State private var browser: LibraryBrowser
    @State private var editor = SessionDraftEditor()
    @State private var browseMode: BrowseMode = .songs
    @State private var navigationPath = NavigationPath()
    @State private var showingAutofillCompletion = false
    @State private var autofillTapCount = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isSearchFieldFocused: Bool

    @Environment(\.libraryPreferences) private var libraryPreferences
    @Environment(\.sessionDraft) private var sessionDraft
    @Environment(\.listeningSessionHost) private var sessionHost
    @Environment(\.shuffleTheme) private var shuffleTheme

    init(
        libraryCatalog: LibraryCatalog,
        initialSortOption: SortOption,
        onDismiss: @escaping () -> Void
    ) {
        self.libraryCatalog = libraryCatalog
        self.onDismiss = onDismiss
        self._browser = State(
            wrappedValue: LibraryBrowser(
                libraryCatalog: libraryCatalog,
                initialSortOption: initialSortOption
            )
        )
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if browser.searchText.isEmpty {
                    browseContentFor(browseMode)
                } else {
                    searchContentFor(browseMode)
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

                if !isSearchFieldFocused && browser.searchText.isEmpty {
                    modernCompletionBar
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilitySortPriority(-1)
        }
        .onChange(of: libraryPreferences?.sortOption) { _, newOption in
            if let newOption {
                browser.handleSortOptionChanged(newOption)
            }
        }
        .task {
            await browser.loadInitialPage()
        }
        .alert("Error", isPresented: .init(
            get: { browser.errorMessage != nil },
            set: { if !$0 { browser.clearError() } }
        )) {
            Button("OK") { browser.clearError() }
        } message: {
            if let error = browser.errorMessage {
                Text(error)
            }
        }
        .animation(.default, value: editor.actionErrorMessage)
        .tint(pickerAccentColor)
    }

    private var modernDiscoveryHeader: some View {
        let style = PickerHeaderStyle.systemDefault

        return VStack(alignment: .leading, spacing: 12) {
            modernSearchField

            HStack(spacing: 10) {
                Picker("Browse", selection: browseModeSelection) {
                    ForEach(BrowseMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("songPicker.scope")
            }

            SessionChangesBanner()
        }
        .animation(reduceMotion ? nil : .snappy, value: sessionHost?.player.hasPendingSessionChanges)
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

            TextField(browseMode == .selected ? "Search your picks" : "Search your library", text: $browser.searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($isSearchFieldFocused)
                .accessibilityIdentifier("songPicker.search")

            if !browser.searchText.isEmpty {
                Button {
                    browser.searchText = ""
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
                            if browser.autofillState == .loading {
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
                    .disabled(browser.autofillState == .loading || showingAutofillCompletion)
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
                    Button(role: .destructive) {
                        showingAutofillCompletion = false
                        editor.clearAll(in: sessionDraft)
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

    /// Switching tabs also switches the browser's lane in the same update,
    /// so the new lane starts loading straight away.
    private var browseModeSelection: Binding<BrowseMode> {
        Binding(
            get: { browseMode },
            set: { mode in
                browseMode = mode
                browser.activeLane = mode.laneKind
            }
        )
    }

    private var pickerAccentColor: Color {
        shuffleTheme.interactionColor
    }

    private var currentSortOption: SortOption {
        libraryPreferences?.sortOption ?? .mostPlayed
    }

    private var sortSelection: Binding<SortOption> {
        Binding(
            get: { currentSortOption },
            set: { libraryPreferences?.sortOption = $0 }
        )
    }

    private var shouldOfferAutofill: Bool {
        sessionDraft.remainingCapacity > 0 && !editor.autofillIsExhausted
    }

    private var completionActionHint: String {
        "Adds available songs up to \(sessionDraft.capacity) total"
    }

    // MARK: - Library Content

    @ViewBuilder
    private func browseContentFor(_ mode: BrowseMode) -> some View {
        switch mode {
        case .songs:
            browseList
        case .artists:
            ArtistListView(
                browser: browser,
                libraryCatalog: libraryCatalog,
                selectedSongIds: selectedSongIds,
                isAtCapacity: sessionDraft.isAtCapacity,
                onToggleSong: toggle
            )
        case .playlists:
            PlaylistListView(
                browser: browser,
                libraryCatalog: libraryCatalog,
                selectedSongIds: selectedSongIds,
                isAtCapacity: sessionDraft.isAtCapacity,
                onToggleSong: toggle
            )
        case .selected:
            selectedList(songs: sessionDraft.songs)
        }
    }

    @ViewBuilder
    private func searchContentFor(_ mode: BrowseMode) -> some View {
        switch mode {
        case .songs: songSearchList
        case .artists: artistSearchList
        case .playlists: playlistSearchList
        case .selected: selectedList(songs: selectedSearchResults)
        }
    }

    // MARK: - Selected Songs

    /// Picked songs matching the search, filtered locally: the draft is
    /// already in memory, so there is no catalog lane to search.
    private var selectedSearchResults: [Song] {
        sessionDraft.songs.filter {
            $0.title.localizedStandardContains(browser.searchText)
                || $0.artist.localizedStandardContains(browser.searchText)
        }
    }

    @ViewBuilder
    private func selectedList(songs: [Song]) -> some View {
        if !songs.isEmpty {
            songList(songs: songs, isPaginated: false)
        } else if browser.searchText.isEmpty {
            ContentUnavailableView(
                "No Songs Selected",
                systemImage: BrowseMode.selected.iconName,
                description: Text("Pick songs from Songs, Artists or Playlists, or use Autofill")
            )
        } else {
            ContentUnavailableView.search(text: browser.searchText)
        }
    }

    // MARK: - Sort

    private var showSortButton: Bool {
        browseMode == .songs && browser.searchText.isEmpty
    }

    // MARK: - Song Browse List

    @ViewBuilder
    private var browseList: some View {
        if browser.browseLoading && browser.browseSongs.isEmpty {
            skeletonList
        } else if browser.browseSongs.isEmpty {
            ContentUnavailableView(
                "No Songs in Library",
                systemImage: "music.note",
                description: Text("Add songs to your Apple Music library to see them here")
            )
        } else {
            songList(songs: browser.browseSongs, isPaginated: true)
        }
    }

    // MARK: - Search Lists

    @ViewBuilder
    private var songSearchList: some View {
        if !browser.searchResults.isEmpty {
            songSearchResultsList
        } else if browser.searchLoading || !browser.hasSearchedOnce {
            skeletonList
        } else {
            ContentUnavailableView.search(text: browser.searchText)
        }
    }

    private var songSearchResultsList: some View {
        let selectedSongIds = selectedSongIds
        let isAtCapacity = sessionDraft.isAtCapacity

        return ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(browser.searchResults) { song in
                    SongRow(
                        song: song,
                        isSelected: selectedSongIds.contains(song.id),
                        isAtCapacity: isAtCapacity,
                        onToggle: { toggle(song) }
                    )
                    .equatable()
                    Divider().padding(.leading, 72)
                }

                if browser.hasMoreSearchResults {
                    ProgressView()
                        .padding()
                        .onAppear {
                            Task { @MainActor in
                                await browser.loadMoreSearchResults()
                            }
                        }
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    @ViewBuilder
    private var artistSearchList: some View {
        if !browser.artistSearchResults.isEmpty {
            artistSearchResultsList
        } else if browser.artistSearchLoading || !browser.hasArtistSearchedOnce {
            skeletonList
        } else {
            ContentUnavailableView.search(text: browser.searchText)
        }
    }

    private var artistSearchResultsList: some View {
        ArtistListView(
            browser: browser,
            libraryCatalog: libraryCatalog,
            selectedSongIds: selectedSongIds,
            isAtCapacity: sessionDraft.isAtCapacity,
            onToggleSong: toggle,
            searchResults: browser.artistSearchResults,
            hasMoreSearchResults: browser.hasMoreArtistSearchResults,
            onLoadMore: { Task { @MainActor in await browser.loadMoreArtistSearchResults() } }
        )
    }

    @ViewBuilder
    private var playlistSearchList: some View {
        if !browser.playlistSearchResults.isEmpty {
            playlistSearchResultsList
        } else if browser.playlistSearchLoading || !browser.hasPlaylistSearchedOnce {
            skeletonList
        } else {
            ContentUnavailableView.search(text: browser.searchText)
        }
    }

    private var playlistSearchResultsList: some View {
        PlaylistListView(
            browser: browser,
            libraryCatalog: libraryCatalog,
            selectedSongIds: selectedSongIds,
            isAtCapacity: sessionDraft.isAtCapacity,
            onToggleSong: toggle,
            searchResults: browser.playlistSearchResults,
            hasMoreSearchResults: browser.hasMorePlaylistSearchResults,
            onLoadMore: { Task { @MainActor in await browser.loadMorePlaylistSearchResults() } }
        )
    }

    // MARK: - Shared Components

    private var skeletonList: some View { SkeletonList() }

    private func songList(songs: [Song], isPaginated: Bool) -> some View {
        let selectedSongIds = selectedSongIds
        let isAtCapacity = sessionDraft.isAtCapacity

        return ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(songs) { song in
                    SongRow(
                        song: song,
                        isSelected: selectedSongIds.contains(song.id),
                        isAtCapacity: isAtCapacity,
                        onToggle: { toggle(song) }
                    )
                    .equatable()
                    Divider().padding(.leading, 72)
                }

                if isPaginated && browser.hasMorePages {
                    ProgressView()
                        .padding()
                        .onAppear {
                            Task { @MainActor in
                                await browser.loadMorePages()
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
                                    browser.resetAutofillState()
                                }
                            }
                        }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private var selectedSongIds: Set<String> {
        Set(sessionDraft.songs.map(\.id))
    }

    private var hasOverlayMessage: Bool {
        editor.actionErrorMessage != nil || showAutofillBanner
    }

    // MARK: - Helpers

    private func toggle(_ song: Song) {
        switch editor.toggle(song, in: sessionDraft) {
        case .added(_, reachedMilestone: true):
            HapticFeedback.milestone.trigger()
        case .added, .removed, .rejectedAtCapacity, .failed:
            // SongRow plays its own feedback, including the nope animation
            // at capacity; a failure shows the error pill.
            break
        }
    }

    private func performAutofill() {
        autofillTapCount += 1
        HapticFeedback.light.trigger()
        Task { @MainActor in
            let requestedCount = sessionDraft.remainingCapacity
            let algorithm = libraryPreferences?.autofillAlgorithm ?? .random
            let source = LibraryAutofillSource(libraryCatalog: libraryCatalog, algorithm: algorithm)
            await browser.autofill(into: sessionDraft, using: source)

            if case .completed(let count) = browser.autofillState {
                showingAutofillCompletion = count > 0
                editor.noteAutofillCompleted(
                    addedCount: count,
                    requestedCount: requestedCount,
                    remainingCapacity: sessionDraft.remainingCapacity
                )
            }
        }
    }

    private var showAutofillBanner: Bool {
        switch browser.autofillState {
        case .completed(let count):
            return count > 0
        case .error:
            return true
        case .idle, .loading:
            return false
        }
    }

    private var autofillMessage: String {
        if case .completed(let count) = browser.autofillState {
            let noun = count == 1 ? "song" : "songs"
            return "Added \(count) \(noun)"
        }
        if case .error(let message) = browser.autofillState {
            return message
        }
        return ""
    }

    private var autofillMessageIsError: Bool {
        if case .error = browser.autofillState {
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
    SongPickerView(
        libraryCatalog: PreviewPickerLibrary.makeService(),
        initialSortOption: .mostPlayed,
        onDismiss: {}
    )
    .environment(\.libraryPreferences, LibraryPreferences())
}

#Preview("With Selected Songs") {
    let draft = SessionDraftStore()
    try? draft.add(Array(PreviewPickerLibrary.sampleSongs.prefix(5)))

    return SongPickerView(
        libraryCatalog: PreviewPickerLibrary.makeService(),
        initialSortOption: .mostPlayed,
        onDismiss: {}
    )
    .environment(\.libraryPreferences, LibraryPreferences())
    .environment(\.sessionDraft, draft)
}

#Preview("Empty Library") {
    SongPickerView(
        libraryCatalog: DeterministicMusicService(),
        initialSortOption: .mostPlayed,
        onDismiss: {}
    )
    .environment(\.libraryPreferences, LibraryPreferences())
}
