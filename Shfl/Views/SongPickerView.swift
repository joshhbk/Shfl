import ShflComposition
import ShflCore
import ShflDeterministic
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

    init(lane: LibraryLaneKind?) {
        switch lane {
        case .songs: self = .songs
        case .artists: self = .artists
        case .playlists: self = .playlists
        case nil: self = .selected
        }
    }

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
    let onDismiss: () -> Void

    @State private var browser: LibraryBrowser
    @State private var editor: SessionDraftEditor
    /// Why the last edit failed, shown for three seconds.
    @State private var draftEditFailure: String?
    @State private var navigationPath = NavigationPath()
    @State private var showingAutofillCompletion = false
    @State private var autofillTapCount = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isSearchFieldFocused: Bool

    @Environment(\.sessionDraft) private var sessionDraft
    @Environment(\.listeningSessionHost) private var sessionHost
    @Environment(\.shuffleTheme) private var shuffleTheme

    /// - Parameter editor: Edits the draft the environment's `sessionDraft`
    ///   shows.
    init(
        browser: LibraryBrowser,
        editor: SessionDraftEditor,
        onDismiss: @escaping () -> Void
    ) {
        self.onDismiss = onDismiss
        self._browser = State(wrappedValue: browser)
        self._editor = State(wrappedValue: editor)
    }

    private var browseMode: BrowseMode {
        BrowseMode(lane: browser.activeLane)
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
            .animation(.default, value: draftEditFailure)
            .accessibilityElement(children: .contain)
            .accessibilitySortPriority(-1)
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
        .accessibilityValue(browser.sortOption.displayName)
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

    private var browseModeSelection: Binding<BrowseMode> {
        Binding(
            get: { browseMode },
            set: { browser.activeLane = $0.laneKind }
        )
    }

    private var pickerAccentColor: Color {
        shuffleTheme.interactionColor
    }

    private var sortSelection: Binding<SortOption> {
        Binding(
            get: { browser.sortOption },
            set: { browser.chooseSortOption($0) }
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
                selectedSongIds: selectedSongIds,
                isAtCapacity: sessionDraft.isAtCapacity,
                onToggleSong: toggle
            )
        case .playlists:
            PlaylistListView(
                browser: browser,
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
                if let draftEditFailure {
                    Text(draftEditFailure)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.red.opacity(0.9), in: Capsule())
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .task(id: draftEditFailure) {
                            guard (try? await Task.sleep(for: .seconds(3))) != nil else { return }
                            self.draftEditFailure = nil
                        }
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
        draftEditFailure != nil || showAutofillBanner
    }

    // MARK: - Helpers

    private func toggle(_ song: Song) {
        switch editor.toggle(song) {
        case .added(_, reachedMilestone: true):
            HapticFeedback.milestone.trigger()
        case .failed(let message):
            draftEditFailure = message
        case .added, .removed, .rejectedAtCapacity:
            // SongRow plays its own feedback, including the nope animation
            // at capacity.
            break
        }
    }

    private func performAutofill() {
        autofillTapCount += 1
        HapticFeedback.light.trigger()
        Task { @MainActor in
            let requestedCount = sessionDraft.remainingCapacity
            await browser.autofill(into: sessionDraft)

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

private struct SongPickerPreview: View {
    @State private var model: AppModel

    init(library: DeterministicLibrary, draft: [Song] = []) {
        _model = State(wrappedValue: AppModel.preview(library: library, draft: draft))
    }

    var body: some View {
        SongPickerView(
            browser: model.makeLibraryBrowser(),
            editor: model.makeDraftEditor(),
            onDismiss: {}
        )
        .environment(\.sessionDraft, model.sessionDraft)
        .environment(model)
    }
}

#Preview("Songs Tab") {
    SongPickerPreview(library: .sample)
}

#Preview("With Selected Songs") {
    SongPickerPreview(library: .sample, draft: Array(DeterministicLibrary.sample.songs.prefix(5)))
}

#Preview("Empty Library") {
    SongPickerPreview(library: .empty)
}
