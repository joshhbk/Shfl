# Library Browser Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace Apple Music catalog search with a user library browser showing most-played songs with pagination.

**Architecture:** Two-mode system (browse/search) using MusicLibraryRequest for paginated browsing and MusicLibrarySearchRequest for text search. LibraryBrowserViewModel manages state for both modes.

**Tech Stack:** SwiftUI, MusicKit (MusicLibraryRequest, MusicLibrarySearchRequest), async/await

---

## Task 1: Add SortOption and LibraryPage Types

**Files:**
- Modify: `Shfl/Domain/Protocols/MusicService.swift`

**Step 1: Add the new types above the protocol**

Add this code at the top of the file, after the imports:

```swift
enum SortOption: Sendable {
    case mostPlayed
    case recentlyPlayed
    case recentlyAdded
    case alphabetical
}

struct LibraryPage: Sendable {
    let songs: [Song]
    let hasMore: Bool
}
```

**Step 2: Build to verify syntax**

Run: `xcodebuild -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

**Step 3: Commit**

```bash
git add Shfl/Domain/Protocols/MusicService.swift
git commit -m "feat: add SortOption and LibraryPage types"
```

---

## Task 2: Update MusicService Protocol

**Files:**
- Modify: `Shfl/Domain/Protocols/MusicService.swift`

**Step 1: Replace searchLibrary with new methods**

Replace this line:
```swift
    /// Search for songs in user's library
    func searchLibrary(query: String) async throws -> [Song]
```

With these methods:
```swift
    /// Fetch songs from user's library with sorting and pagination
    func fetchLibrarySongs(
        sortedBy: SortOption,
        limit: Int,
        offset: Int
    ) async throws -> LibraryPage

    /// Search user's library for songs matching query
    func searchLibrarySongs(query: String) async throws -> [Song]
```

**Step 2: Build (expect errors)**

Run: `xcodebuild -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | grep -E "error:|BUILD"`
Expected: Errors in AppleMusicService.swift, MockMusicService.swift (protocol conformance)

**Step 3: Commit**

```bash
git add Shfl/Domain/Protocols/MusicService.swift
git commit -m "feat: update MusicService protocol with library browsing methods"
```

---

## Task 3: Implement AppleMusicService Library Methods

**Files:**
- Modify: `Shfl/Services/AppleMusicService.swift`

**Step 1: Replace searchLibrary with fetchLibrarySongs**

Replace the existing `searchLibrary` method (lines 28-42) with:

```swift
    func fetchLibrarySongs(
        sortedBy: SortOption,
        limit: Int,
        offset: Int
    ) async throws -> LibraryPage {
        var request = MusicLibraryRequest<MusicKit.Song>()

        switch sortedBy {
        case .mostPlayed:
            request.sort(by: \.playCount, ascending: false)
        case .recentlyPlayed:
            request.sort(by: \.lastPlayedDate, ascending: false)
        case .recentlyAdded:
            request.sort(by: \.libraryAddedDate, ascending: false)
        case .alphabetical:
            request.sort(by: \.title, ascending: true)
        }

        let response = try await request.response()

        // Manual pagination since MusicLibraryRequest doesn't support offset
        let allSongs = response.items.map { musicKitSong in
            Song(
                id: musicKitSong.id.rawValue,
                title: musicKitSong.title,
                artist: musicKitSong.artistName,
                albumTitle: musicKitSong.albumTitle ?? "",
                artworkURL: musicKitSong.artwork?.url(width: 300, height: 300)
            )
        }

        let startIndex = min(offset, allSongs.count)
        let endIndex = min(offset + limit, allSongs.count)
        let pageItems = Array(allSongs[startIndex..<endIndex])
        let hasMore = endIndex < allSongs.count

        return LibraryPage(songs: pageItems, hasMore: hasMore)
    }
```

**Step 2: Add searchLibrarySongs method**

Add after fetchLibrarySongs:

```swift
    func searchLibrarySongs(query: String) async throws -> [Song] {
        var request = MusicLibrarySearchRequest(term: query, types: [MusicKit.Song.self])
        let response = try await request.response()

        return response.songs.map { musicKitSong in
            Song(
                id: musicKitSong.id.rawValue,
                title: musicKitSong.title,
                artist: musicKitSong.artistName,
                albumTitle: musicKitSong.albumTitle ?? "",
                artworkURL: musicKitSong.artwork?.url(width: 300, height: 300)
            )
        }
    }
```

**Step 3: Build (expect errors)**

Run: `xcodebuild -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | grep -E "error:|BUILD"`
Expected: Errors in MockMusicService.swift, SongPickerView.swift

**Step 4: Commit**

```bash
git add Shfl/Services/AppleMusicService.swift
git commit -m "feat: implement library browsing in AppleMusicService"
```

---

## Task 4: Update MockMusicService

**Files:**
- Modify: `ShflTests/Mocks/MockMusicService.swift`

**Step 1: Add new properties for testing**

Add after existing properties (around line 9):

```swift
    var librarySongs: [Song] = []
    var shouldThrowOnFetch: Error?
```

**Step 2: Replace searchLibrary with new methods**

Replace the `searchLibrary` method (around lines 35-43) with:

```swift
    func fetchLibrarySongs(
        sortedBy: SortOption,
        limit: Int,
        offset: Int
    ) async throws -> LibraryPage {
        if let error = shouldThrowOnFetch {
            throw error
        }
        let startIndex = min(offset, librarySongs.count)
        let endIndex = min(offset + limit, librarySongs.count)
        let pageItems = Array(librarySongs[startIndex..<endIndex])
        let hasMore = endIndex < librarySongs.count
        return LibraryPage(songs: pageItems, hasMore: hasMore)
    }

    func searchLibrarySongs(query: String) async throws -> [Song] {
        if let error = shouldThrowOnSearch {
            throw error
        }
        return librarySongs.filter {
            $0.title.localizedCaseInsensitiveContains(query) ||
            $0.artist.localizedCaseInsensitiveContains(query)
        }
    }
```

**Step 3: Update test helper**

Replace `setSearchResults` method with:

```swift
    func setLibrarySongs(_ songs: [Song]) {
        librarySongs = songs
    }
```

**Step 4: Build (expect errors)**

Run: `xcodebuild -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | grep -E "error:|BUILD"`
Expected: Errors in SongPickerView.swift (still using old method)

**Step 5: Commit**

```bash
git add ShflTests/Mocks/MockMusicService.swift
git commit -m "feat: update MockMusicService with library browsing methods"
```

---

## Task 5: Create SkeletonSongRow Component

**Files:**
- Create: `Shfl/Views/Components/SkeletonSongRow.swift`
- Create: `ShflTests/Views/SkeletonSongRowTests.swift`

**Step 1: Write the test file**

Create `ShflTests/Views/SkeletonSongRowTests.swift`:

```swift
import XCTest
@testable import Shfl

final class SkeletonSongRowTests: XCTestCase {

    func test_skeletonRow_hasCorrectDimensions() {
        // SkeletonSongRow should match SongRow layout
        // This is a structural test - the component exists and renders
        let row = SkeletonSongRow()
        XCTAssertNotNil(row)
    }

    func test_shimmerEffect_defaultsToTrue() {
        let row = SkeletonSongRow()
        XCTAssertTrue(row.animate)
    }

    func test_shimmerEffect_canBeDisabled() {
        let row = SkeletonSongRow(animate: false)
        XCTAssertFalse(row.animate)
    }
}
```

**Step 2: Run test (expect failure)**

Run: `xcodebuild test -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:ShflTests/SkeletonSongRowTests 2>&1 | tail -10`
Expected: Build failure - SkeletonSongRow not found

**Step 3: Create the component**

Create `Shfl/Views/Components/SkeletonSongRow.swift`:

```swift
import SwiftUI

struct SkeletonSongRow: View {
    let animate: Bool

    init(animate: Bool = true) {
        self.animate = animate
    }

    @State private var shimmerOffset: CGFloat = -200

    var body: some View {
        HStack(spacing: 12) {
            // Album art placeholder
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.gray.opacity(0.2))
                .frame(width: 48, height: 48)
                .overlay(shimmerOverlay)

            VStack(alignment: .leading, spacing: 6) {
                // Title placeholder
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 140, height: 14)
                    .overlay(shimmerOverlay)

                // Artist placeholder
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 100, height: 12)
                    .overlay(shimmerOverlay)
            }

            Spacer()

            // Checkbox placeholder
            Circle()
                .fill(Color.gray.opacity(0.2))
                .frame(width: 22, height: 22)
                .overlay(shimmerOverlay)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .onAppear {
            guard animate else { return }
            withAnimation(
                .linear(duration: 1.5)
                .repeatForever(autoreverses: false)
            ) {
                shimmerOffset = 200
            }
        }
    }

    @ViewBuilder
    private var shimmerOverlay: some View {
        if animate {
            LinearGradient(
                colors: [
                    .clear,
                    .white.opacity(0.4),
                    .clear
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .offset(x: shimmerOffset)
            .clipped()
        }
    }
}

#Preview {
    VStack(spacing: 0) {
        SkeletonSongRow()
        Divider().padding(.leading, 72)
        SkeletonSongRow()
        Divider().padding(.leading, 72)
        SkeletonSongRow()
    }
}
```

**Step 4: Run tests**

Run: `xcodebuild test -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:ShflTests/SkeletonSongRowTests 2>&1 | tail -10`
Expected: `** TEST SUCCEEDED **`

**Step 5: Commit**

```bash
git add Shfl/Views/Components/SkeletonSongRow.swift ShflTests/Views/SkeletonSongRowTests.swift
git commit -m "feat: add SkeletonSongRow loading placeholder component"
```

---

## Task 6: Create LibraryBrowserViewModel - Core Structure

**Files:**
- Create: `Shfl/ViewModels/LibraryBrowserViewModel.swift`
- Create: `ShflTests/ViewModels/LibraryBrowserViewModelTests.swift`

**Step 1: Write initial tests**

Create `ShflTests/ViewModels/LibraryBrowserViewModelTests.swift`:

```swift
import XCTest
@testable import Shfl

@MainActor
final class LibraryBrowserViewModelTests: XCTestCase {
    private var mockService: MockMusicService!
    private var viewModel: LibraryBrowserViewModel!

    override func setUp() async throws {
        mockService = MockMusicService()
        viewModel = LibraryBrowserViewModel(musicService: mockService)
    }

    func test_initialState_isCorrect() {
        XCTAssertTrue(viewModel.browseSongs.isEmpty)
        XCTAssertTrue(viewModel.searchResults.isEmpty)
        XCTAssertEqual(viewModel.searchText, "")
        XCTAssertEqual(viewModel.currentMode, .browse)
        XCTAssertFalse(viewModel.isLoading)
    }

    func test_currentMode_switchesToSearchWhenTextEntered() {
        viewModel.searchText = "test"
        XCTAssertEqual(viewModel.currentMode, .search)
    }

    func test_currentMode_switchesToBrowseWhenTextCleared() {
        viewModel.searchText = "test"
        viewModel.searchText = ""
        XCTAssertEqual(viewModel.currentMode, .browse)
    }
}
```

**Step 2: Run tests (expect failure)**

Run: `xcodebuild test -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:ShflTests/LibraryBrowserViewModelTests 2>&1 | tail -10`
Expected: Build failure - LibraryBrowserViewModel not found

**Step 3: Create the ViewModel**

Create `Shfl/ViewModels/LibraryBrowserViewModel.swift`:

```swift
import Combine
import Foundation

@MainActor
final class LibraryBrowserViewModel: ObservableObject {
    enum Mode: Equatable {
        case browse
        case search
    }

    // Browse state
    @Published private(set) var browseSongs: [Song] = []
    @Published private(set) var browseLoading = false
    @Published private(set) var hasMorePages = true
    @Published var sortOption: SortOption = .mostPlayed

    // Search state
    @Published private(set) var searchResults: [Song] = []
    @Published private(set) var searchLoading = false

    // Shared state
    @Published var searchText = ""
    @Published private(set) var errorMessage: String?

    var currentMode: Mode {
        searchText.isEmpty ? .browse : .search
    }

    var isLoading: Bool {
        currentMode == .browse ? browseLoading : searchLoading
    }

    var displayedSongs: [Song] {
        currentMode == .browse ? browseSongs : searchResults
    }

    // Pagination
    private let pageSize = 50
    private var currentOffset = 0
    private var isLoadingMore = false

    // Dependencies
    private let musicService: MusicService
    private var searchTask: Task<Void, Never>?

    init(musicService: MusicService) {
        self.musicService = musicService
    }
}
```

**Step 4: Run tests**

Run: `xcodebuild test -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:ShflTests/LibraryBrowserViewModelTests 2>&1 | tail -10`
Expected: `** TEST SUCCEEDED **`

**Step 5: Commit**

```bash
git add Shfl/ViewModels/LibraryBrowserViewModel.swift ShflTests/ViewModels/LibraryBrowserViewModelTests.swift
git commit -m "feat: add LibraryBrowserViewModel core structure"
```

---

## Task 7: Add Browse Pagination to ViewModel

**Files:**
- Modify: `Shfl/ViewModels/LibraryBrowserViewModel.swift`
- Modify: `ShflTests/ViewModels/LibraryBrowserViewModelTests.swift`

**Step 1: Add pagination tests**

Add to `LibraryBrowserViewModelTests.swift`:

```swift
    func test_loadInitialPage_fetchesSongs() async {
        let songs = [
            Song(id: "1", title: "Song 1", artist: "Artist", albumTitle: "Album", artworkURL: nil),
            Song(id: "2", title: "Song 2", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        ]
        await mockService.setLibrarySongs(songs)

        await viewModel.loadInitialPage()

        XCTAssertEqual(viewModel.browseSongs.count, 2)
        XCTAssertFalse(viewModel.browseLoading)
    }

    func test_loadInitialPage_setsHasMorePages() async {
        // Create more songs than page size to test pagination
        let songs = (1...60).map {
            Song(id: "\($0)", title: "Song \($0)", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        }
        await mockService.setLibrarySongs(songs)

        await viewModel.loadInitialPage()

        XCTAssertEqual(viewModel.browseSongs.count, 50)
        XCTAssertTrue(viewModel.hasMorePages)
    }

    func test_loadNextPage_appendsSongs() async {
        let songs = (1...60).map {
            Song(id: "\($0)", title: "Song \($0)", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        }
        await mockService.setLibrarySongs(songs)

        await viewModel.loadInitialPage()
        await viewModel.loadNextPageIfNeeded(currentSong: viewModel.browseSongs.last!)

        XCTAssertEqual(viewModel.browseSongs.count, 60)
        XCTAssertFalse(viewModel.hasMorePages)
    }
```

**Step 2: Run tests (expect failure)**

Run: `xcodebuild test -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:ShflTests/LibraryBrowserViewModelTests 2>&1 | grep -E "error:|failed|TEST"`
Expected: Failures - methods not implemented

**Step 3: Implement pagination methods**

Add to `LibraryBrowserViewModel.swift` at the end of the class:

```swift
    // MARK: - Browse Methods

    func loadInitialPage() async {
        browseLoading = true
        currentOffset = 0
        browseSongs = []

        do {
            let page = try await musicService.fetchLibrarySongs(
                sortedBy: sortOption,
                limit: pageSize,
                offset: 0
            )
            browseSongs = page.songs
            hasMorePages = page.hasMore
            currentOffset = page.songs.count
        } catch {
            errorMessage = error.localizedDescription
        }

        browseLoading = false
    }

    func loadNextPageIfNeeded(currentSong: Song) async {
        guard hasMorePages,
              !isLoadingMore,
              currentSong.id == browseSongs.last?.id else {
            return
        }

        isLoadingMore = true

        do {
            let page = try await musicService.fetchLibrarySongs(
                sortedBy: sortOption,
                limit: pageSize,
                offset: currentOffset
            )
            browseSongs.append(contentsOf: page.songs)
            hasMorePages = page.hasMore
            currentOffset += page.songs.count
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoadingMore = false
    }
```

**Step 4: Run tests**

Run: `xcodebuild test -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:ShflTests/LibraryBrowserViewModelTests 2>&1 | tail -10`
Expected: `** TEST SUCCEEDED **`

**Step 5: Commit**

```bash
git add Shfl/ViewModels/LibraryBrowserViewModel.swift ShflTests/ViewModels/LibraryBrowserViewModelTests.swift
git commit -m "feat: add browse pagination to LibraryBrowserViewModel"
```

---

## Task 8: Add Search to ViewModel

**Files:**
- Modify: `Shfl/ViewModels/LibraryBrowserViewModel.swift`
- Modify: `ShflTests/ViewModels/LibraryBrowserViewModelTests.swift`

**Step 1: Add search tests**

Add to `LibraryBrowserViewModelTests.swift`:

```swift
    func test_performSearch_fetchesResults() async {
        let songs = [
            Song(id: "1", title: "Hello World", artist: "Artist", albumTitle: "Album", artworkURL: nil),
            Song(id: "2", title: "Goodbye", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        ]
        await mockService.setLibrarySongs(songs)

        await viewModel.performSearch(query: "Hello")

        XCTAssertEqual(viewModel.searchResults.count, 1)
        XCTAssertEqual(viewModel.searchResults.first?.title, "Hello World")
    }

    func test_performSearch_clearsResultsForEmptyQuery() async {
        let songs = [
            Song(id: "1", title: "Hello", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        ]
        await mockService.setLibrarySongs(songs)
        await viewModel.performSearch(query: "Hello")

        await viewModel.performSearch(query: "")

        XCTAssertTrue(viewModel.searchResults.isEmpty)
    }
```

**Step 2: Run tests (expect failure)**

Run: `xcodebuild test -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:ShflTests/LibraryBrowserViewModelTests 2>&1 | grep -E "error:|failed|TEST"`
Expected: Failures - performSearch not implemented

**Step 3: Implement search method**

Add to `LibraryBrowserViewModel.swift`:

```swift
    // MARK: - Search Methods

    func performSearch(query: String) async {
        guard !query.isEmpty else {
            searchResults = []
            return
        }

        searchLoading = true

        do {
            searchResults = try await musicService.searchLibrarySongs(query: query)
        } catch {
            errorMessage = error.localizedDescription
        }

        searchLoading = false
    }

    func setupSearchDebounce() {
        // Call this from the view to set up debounced search
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
            guard !Task.isCancelled else { return }
            await performSearch(query: searchText)
        }
    }
```

**Step 4: Run tests**

Run: `xcodebuild test -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:ShflTests/LibraryBrowserViewModelTests 2>&1 | tail -10`
Expected: `** TEST SUCCEEDED **`

**Step 5: Commit**

```bash
git add Shfl/ViewModels/LibraryBrowserViewModel.swift ShflTests/ViewModels/LibraryBrowserViewModelTests.swift
git commit -m "feat: add search functionality to LibraryBrowserViewModel"
```

---

## Task 9: Update SongPickerView

**Files:**
- Modify: `Shfl/Views/SongPickerView.swift`

**Step 1: Replace the entire file**

Replace `Shfl/Views/SongPickerView.swift` with:

```swift
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
            }
            .navigationTitle("Add Songs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDismiss)
                }
            }
            .searchable(text: $viewModel.searchText, prompt: "Search your library")
            .onChange(of: viewModel.searchText) { _, _ in
                viewModel.setupSearchDebounce()
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
}
```

**Step 2: Add clearError method to ViewModel**

Add to `LibraryBrowserViewModel.swift`:

```swift
    func clearError() {
        errorMessage = nil
    }
```

**Step 3: Build**

Run: `xcodebuild -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

**Step 4: Commit**

```bash
git add Shfl/Views/SongPickerView.swift Shfl/ViewModels/LibraryBrowserViewModel.swift
git commit -m "feat: integrate LibraryBrowserViewModel into SongPickerView"
```

---

## Task 10: Update MockMusicService in App

**Files:**
- Modify: `Shfl/Services/MockMusicService.swift`

**Step 1: Update the app's MockMusicService**

Replace `Shfl/Services/MockMusicService.swift` with:

```swift
import Foundation

final class MockMusicService: MusicService, @unchecked Sendable {
    var isAuthorized: Bool { true }

    var playbackStateStream: AsyncStream<PlaybackState> {
        AsyncStream { continuation in
            continuation.yield(.empty)
        }
    }

    func requestAuthorization() async -> Bool { true }

    func fetchLibrarySongs(
        sortedBy: SortOption,
        limit: Int,
        offset: Int
    ) async throws -> LibraryPage {
        LibraryPage(songs: [], hasMore: false)
    }

    func searchLibrarySongs(query: String) async throws -> [Song] {
        []
    }

    func setQueue(songs: [Song]) async throws {}
    func play() async throws {}
    func pause() async {}
    func skipToNext() async throws {}
}
```

**Step 2: Build**

Run: `xcodebuild -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

**Step 3: Commit**

```bash
git add Shfl/Services/MockMusicService.swift
git commit -m "feat: update app MockMusicService with new protocol methods"
```

---

## Task 11: Run All Tests

**Files:** None (verification only)

**Step 1: Run full test suite**

Run: `xcodebuild test -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | grep -E "Test Suite|passed|failed|TEST"`
Expected: All tests pass

**Step 2: If tests fail, fix and re-run**

Check specific failures and address them.

**Step 3: Final commit**

```bash
git add -A
git commit -m "test: ensure all tests pass with library browser feature"
```

---

## Task 12: Manual Testing Checklist

Test on device or simulator with Apple Music subscription:

- [ ] Open song picker - see skeleton loading states
- [ ] Library loads sorted by most played
- [ ] Scroll to bottom - more songs load (pagination)
- [ ] Type in search - switches to search mode
- [ ] Search results filter from library
- [ ] Clear search - returns to browse mode
- [ ] Add/remove songs works correctly
- [ ] Undo pill appears and functions
- [ ] Capacity bar updates correctly
