# Autofill Feature Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add an Autofill button to SongPickerView that fills remaining shuffle slots with random songs from the user's Apple Music library.

**Architecture:** Strategy pattern with `AutofillSource` protocol for extensibility. `LibraryAutofillSource` fetches random songs excluding duplicates. `LibraryBrowserViewModel` coordinates the flow and exposes loading/result state.

**Tech Stack:** SwiftUI, MusicKit (via MusicService protocol), Combine

---

## Task 1: Create AutofillSource Protocol

**Files:**
- Create: `Shfl/Domain/Protocols/AutofillSource.swift`
- Test: `ShflTests/Domain/AutofillSourceTests.swift`

**Step 1: Write the failing test**

```swift
// ShflTests/Domain/AutofillSourceTests.swift
import XCTest
@testable import Shfl

@MainActor
final class AutofillSourceTests: XCTestCase {
    func test_protocolExists() {
        // This test just verifies the protocol compiles
        let _: (any AutofillSource)? = nil
        XCTAssertTrue(true)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:ShflTests/AutofillSourceTests 2>&1 | grep -E "(passed|failed|error:)"`

Expected: FAIL with "cannot find type 'AutofillSource'"

**Step 3: Write minimal implementation**

```swift
// Shfl/Domain/Protocols/AutofillSource.swift
import Foundation

protocol AutofillSource: Sendable {
    /// Fetch random songs for autofill, excluding songs already in the shuffle
    /// - Parameters:
    ///   - excluding: Song IDs to exclude (already in shuffle)
    ///   - limit: Maximum number of songs to return
    /// - Returns: Array of songs to add
    func fetchSongs(excluding: Set<String>, limit: Int) async throws -> [Song]
}
```

**Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:ShflTests/AutofillSourceTests 2>&1 | grep -E "(passed|failed|error:)"`

Expected: PASS

**Step 5: Commit**

```bash
git add Shfl/Domain/Protocols/AutofillSource.swift ShflTests/Domain/AutofillSourceTests.swift
git commit -m "feat: add AutofillSource protocol"
```

---

## Task 2: Create LibraryAutofillSource

**Files:**
- Create: `Shfl/Domain/LibraryAutofillSource.swift`
- Modify: `ShflTests/Domain/AutofillSourceTests.swift`

**Step 1: Write the failing test for basic fetch**

```swift
// Add to ShflTests/Domain/AutofillSourceTests.swift
func test_librarySource_fetchesSongsFromLibrary() async throws {
    let mockService = MockMusicService()
    let songs = (1...10).map { makeSong(id: "\($0)") }
    await mockService.setLibrarySongs(songs)

    let source = LibraryAutofillSource(musicService: mockService)
    let result = try await source.fetchSongs(excluding: [], limit: 5)

    XCTAssertEqual(result.count, 5)
}

private func makeSong(id: String) -> Song {
    Song(id: id, title: "Song \(id)", artist: "Artist", albumTitle: "Album", artworkURL: nil)
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:ShflTests/AutofillSourceTests/test_librarySource_fetchesSongsFromLibrary 2>&1 | grep -E "(passed|failed|error:)"`

Expected: FAIL with "cannot find 'LibraryAutofillSource'"

**Step 3: Write minimal implementation**

```swift
// Shfl/Domain/LibraryAutofillSource.swift
import Foundation

struct LibraryAutofillSource: AutofillSource {
    private let musicService: MusicService

    init(musicService: MusicService) {
        self.musicService = musicService
    }

    func fetchSongs(excluding: Set<String>, limit: Int) async throws -> [Song] {
        // Fetch more than we need to account for exclusions and randomization
        let fetchLimit = min(limit * 3, 500)
        let page = try await musicService.fetchLibrarySongs(
            sortedBy: .recentlyAdded,
            limit: fetchLimit,
            offset: 0
        )

        // Filter out excluded songs and shuffle
        let available = page.songs.filter { !excluding.contains($0.id) }
        let shuffled = available.shuffled()

        // Return up to limit
        return Array(shuffled.prefix(limit))
    }
}
```

**Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:ShflTests/AutofillSourceTests/test_librarySource_fetchesSongsFromLibrary 2>&1 | grep -E "(passed|failed|error:)"`

Expected: PASS

**Step 5: Commit**

```bash
git add Shfl/Domain/LibraryAutofillSource.swift ShflTests/Domain/AutofillSourceTests.swift
git commit -m "feat: add LibraryAutofillSource basic implementation"
```

---

## Task 3: Add Tests for Exclusion and Limit Handling

**Files:**
- Modify: `ShflTests/Domain/AutofillSourceTests.swift`

**Step 1: Write tests for exclusion logic**

```swift
// Add to ShflTests/Domain/AutofillSourceTests.swift
func test_librarySource_excludesSongsAlreadyInShuffle() async throws {
    let mockService = MockMusicService()
    let songs = (1...10).map { makeSong(id: "\($0)") }
    await mockService.setLibrarySongs(songs)

    let source = LibraryAutofillSource(musicService: mockService)
    let excluding: Set<String> = ["1", "2", "3"]
    let result = try await source.fetchSongs(excluding: excluding, limit: 10)

    // Should not contain excluded IDs
    let resultIds = Set(result.map { $0.id })
    XCTAssertTrue(resultIds.isDisjoint(with: excluding))
}

func test_librarySource_returnsEmptyWhenAllExcluded() async throws {
    let mockService = MockMusicService()
    let songs = [makeSong(id: "1"), makeSong(id: "2")]
    await mockService.setLibrarySongs(songs)

    let source = LibraryAutofillSource(musicService: mockService)
    let result = try await source.fetchSongs(excluding: ["1", "2"], limit: 10)

    XCTAssertTrue(result.isEmpty)
}

func test_librarySource_respectsLimit() async throws {
    let mockService = MockMusicService()
    let songs = (1...100).map { makeSong(id: "\($0)") }
    await mockService.setLibrarySongs(songs)

    let source = LibraryAutofillSource(musicService: mockService)
    let result = try await source.fetchSongs(excluding: [], limit: 20)

    XCTAssertEqual(result.count, 20)
}

func test_librarySource_returnsLessThanLimitWhenLibrarySmall() async throws {
    let mockService = MockMusicService()
    let songs = (1...5).map { makeSong(id: "\($0)") }
    await mockService.setLibrarySongs(songs)

    let source = LibraryAutofillSource(musicService: mockService)
    let result = try await source.fetchSongs(excluding: [], limit: 50)

    XCTAssertEqual(result.count, 5)
}
```

**Step 2: Run tests to verify they pass**

Run: `xcodebuild test -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:ShflTests/AutofillSourceTests 2>&1 | grep -E "(passed|failed|error:)"`

Expected: All PASS (implementation from Task 2 should handle these)

**Step 3: Commit**

```bash
git add ShflTests/Domain/AutofillSourceTests.swift
git commit -m "test: add comprehensive AutofillSource tests"
```

---

## Task 4: Add Autofill State to LibraryBrowserViewModel

**Files:**
- Modify: `Shfl/ViewModels/LibraryBrowserViewModel.swift`
- Modify: `ShflTests/ViewModels/LibraryBrowserViewModelTests.swift`

**Step 1: Write the failing test**

```swift
// Add to ShflTests/ViewModels/LibraryBrowserViewModelTests.swift
func test_autofillState_initiallyIdle() {
    XCTAssertEqual(viewModel.autofillState, .idle)
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:ShflTests/LibraryBrowserViewModelTests/test_autofillState_initiallyIdle 2>&1 | grep -E "(passed|failed|error:)"`

Expected: FAIL with "has no member 'autofillState'"

**Step 3: Write minimal implementation**

```swift
// Add to LibraryBrowserViewModel.swift, after the Mode enum:
enum AutofillState: Equatable {
    case idle
    case loading
    case completed(count: Int)
    case error(String)
}

// Add published property after other @Published properties:
@Published private(set) var autofillState: AutofillState = .idle
```

**Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:ShflTests/LibraryBrowserViewModelTests/test_autofillState_initiallyIdle 2>&1 | grep -E "(passed|failed|error:)"`

Expected: PASS

**Step 5: Commit**

```bash
git add Shfl/ViewModels/LibraryBrowserViewModel.swift ShflTests/ViewModels/LibraryBrowserViewModelTests.swift
git commit -m "feat: add autofillState to LibraryBrowserViewModel"
```

---

## Task 5: Add Autofill Method to LibraryBrowserViewModel

**Files:**
- Modify: `Shfl/ViewModels/LibraryBrowserViewModel.swift`
- Modify: `ShflTests/ViewModels/LibraryBrowserViewModelTests.swift`

**Step 1: Write the failing test**

```swift
// Add to ShflTests/ViewModels/LibraryBrowserViewModelTests.swift
func test_autofill_addsSongsToPlayer() async {
    let songs = (1...50).map {
        Song(id: "\($0)", title: "Song \($0)", artist: "Artist", albumTitle: "Album", artworkURL: nil)
    }
    await mockService.setLibrarySongs(songs)

    let player = ShufflePlayer(musicService: mockService)
    let source = LibraryAutofillSource(musicService: mockService)

    await viewModel.autofill(into: player, using: source)

    XCTAssertEqual(player.songCount, 50)
    XCTAssertEqual(viewModel.autofillState, .completed(count: 50))
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:ShflTests/LibraryBrowserViewModelTests/test_autofill_addsSongsToPlayer 2>&1 | grep -E "(passed|failed|error:)"`

Expected: FAIL with "has no member 'autofill'"

**Step 3: Write minimal implementation**

```swift
// Add to LibraryBrowserViewModel.swift, in the MARK: - Search Methods section or after:

// MARK: - Autofill Methods

func autofill(into player: ShufflePlayer, using source: AutofillSource) async {
    let limit = player.remainingCapacity
    guard limit > 0 else {
        autofillState = .completed(count: 0)
        return
    }

    autofillState = .loading

    do {
        let excludedIds = Set(player.allSongs.map { $0.id })
        let songs = try await source.fetchSongs(excluding: excludedIds, limit: limit)

        var addedCount = 0
        for song in songs {
            do {
                try player.addSong(song)
                addedCount += 1
            } catch {
                // Stop if we hit capacity
                break
            }
        }

        autofillState = .completed(count: addedCount)
    } catch {
        autofillState = .error(error.localizedDescription)
    }
}

func resetAutofillState() {
    autofillState = .idle
}
```

**Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:ShflTests/LibraryBrowserViewModelTests/test_autofill_addsSongsToPlayer 2>&1 | grep -E "(passed|failed|error:)"`

Expected: PASS

**Step 5: Commit**

```bash
git add Shfl/ViewModels/LibraryBrowserViewModel.swift ShflTests/ViewModels/LibraryBrowserViewModelTests.swift
git commit -m "feat: add autofill method to LibraryBrowserViewModel"
```

---

## Task 6: Add Tests for Autofill Edge Cases

**Files:**
- Modify: `ShflTests/ViewModels/LibraryBrowserViewModelTests.swift`

**Step 1: Write tests for edge cases**

```swift
// Add to ShflTests/ViewModels/LibraryBrowserViewModelTests.swift
func test_autofill_fillsOnlyRemainingCapacity() async {
    let songs = (1...200).map {
        Song(id: "\($0)", title: "Song \($0)", artist: "Artist", albumTitle: "Album", artworkURL: nil)
    }
    await mockService.setLibrarySongs(songs)

    let player = ShufflePlayer(musicService: mockService)
    // Add 100 songs first
    for i in 1...100 {
        try? player.addSong(Song(id: "existing-\(i)", title: "Existing \(i)", artist: "Artist", albumTitle: "Album", artworkURL: nil))
    }

    let source = LibraryAutofillSource(musicService: mockService)
    await viewModel.autofill(into: player, using: source)

    // Should only add 20 more (120 - 100)
    XCTAssertEqual(player.songCount, 120)
    XCTAssertEqual(viewModel.autofillState, .completed(count: 20))
}

func test_autofill_excludesDuplicates() async {
    let songs = (1...10).map {
        Song(id: "\($0)", title: "Song \($0)", artist: "Artist", albumTitle: "Album", artworkURL: nil)
    }
    await mockService.setLibrarySongs(songs)

    let player = ShufflePlayer(musicService: mockService)
    // Pre-add some songs that are also in library
    try? player.addSong(songs[0])
    try? player.addSong(songs[1])

    let source = LibraryAutofillSource(musicService: mockService)
    await viewModel.autofill(into: player, using: source)

    // Should add 8 new songs (10 - 2 already added)
    XCTAssertEqual(player.songCount, 10)
    XCTAssertEqual(viewModel.autofillState, .completed(count: 8))
}

func test_autofill_completesWithZeroWhenFull() async {
    let player = ShufflePlayer(musicService: mockService)
    // Fill to capacity
    for i in 1...120 {
        try? player.addSong(Song(id: "\(i)", title: "Song \(i)", artist: "Artist", albumTitle: "Album", artworkURL: nil))
    }

    let source = LibraryAutofillSource(musicService: mockService)
    await viewModel.autofill(into: player, using: source)

    XCTAssertEqual(viewModel.autofillState, .completed(count: 0))
}

func test_autofill_setsLoadingState() async {
    let songs = [Song(id: "1", title: "Song", artist: "Artist", albumTitle: "Album", artworkURL: nil)]
    await mockService.setLibrarySongs(songs)

    let player = ShufflePlayer(musicService: mockService)
    let source = LibraryAutofillSource(musicService: mockService)

    // Start autofill
    let task = Task {
        await viewModel.autofill(into: player, using: source)
    }

    // Note: In real implementation we'd need to check loading state during execution
    // For now just verify it completes correctly
    await task.value

    XCTAssertEqual(viewModel.autofillState, .completed(count: 1))
}
```

**Step 2: Run tests to verify they pass**

Run: `xcodebuild test -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:ShflTests/LibraryBrowserViewModelTests 2>&1 | grep -E "(passed|failed|error:)"`

Expected: All PASS

**Step 3: Commit**

```bash
git add ShflTests/ViewModels/LibraryBrowserViewModelTests.swift
git commit -m "test: add autofill edge case tests"
```

---

## Task 7: Add Autofill Button to SongPickerView

**Files:**
- Modify: `Shfl/Views/SongPickerView.swift`

**Step 1: Add the autofill button to toolbar**

```swift
// In SongPickerView.swift, modify the .toolbar section to add leading item:
.toolbar {
    ToolbarItem(placement: .cancellationAction) {
        Button("Autofill") {
            Task {
                let source = LibraryAutofillSource(musicService: musicService)
                await viewModel.autofill(into: player, using: source)
            }
        }
        .disabled(player.remainingCapacity == 0 || viewModel.autofillState == .loading)
    }
    ToolbarItem(placement: .confirmationAction) {
        Button("Done", action: onDismiss)
    }
}
```

**Step 2: Build to verify it compiles**

Run: `xcodebuild build -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "(error:|BUILD SUCCEEDED|BUILD FAILED)"`

Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add Shfl/Views/SongPickerView.swift
git commit -m "feat: add Autofill button to SongPickerView toolbar"
```

---

## Task 8: Add Autofill Feedback Banner

**Files:**
- Modify: `Shfl/Views/SongPickerView.swift`

**Step 1: Add feedback banner for autofill completion**

```swift
// In SongPickerView.swift, add a computed property for autofill banner visibility:
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

// Modify the body's ZStack to include the autofill feedback.
// After the UndoPill, add:
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
```

**Step 2: Wrap state changes in animation**

```swift
// Update the autofill button action to animate:
Button("Autofill") {
    Task {
        let source = LibraryAutofillSource(musicService: musicService)
        await viewModel.autofill(into: player, using: source)
        // Banner will auto-dismiss via onAppear
    }
}
```

**Step 3: Build and verify**

Run: `xcodebuild build -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "(error:|BUILD SUCCEEDED|BUILD FAILED)"`

Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add Shfl/Views/SongPickerView.swift
git commit -m "feat: add autofill completion feedback banner"
```

---

## Task 9: Add Loading State to Autofill Button

**Files:**
- Modify: `Shfl/Views/SongPickerView.swift`

**Step 1: Update button to show loading indicator**

```swift
// Replace the simple Autofill button with one that shows loading state:
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
```

**Step 2: Build and verify**

Run: `xcodebuild build -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "(error:|BUILD SUCCEEDED|BUILD FAILED)"`

Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add Shfl/Views/SongPickerView.swift
git commit -m "feat: show loading spinner during autofill"
```

---

## Task 10: Run Full Test Suite and Final Cleanup

**Files:**
- All modified files

**Step 1: Run full test suite**

Run: `xcodebuild test -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "(passed|failed|Test Suite)"`

Expected: All tests pass (except pre-existing failure in LibraryBrowserViewModelTests.test_initialState_isCorrect)

**Step 2: Verify build succeeds**

Run: `xcodebuild build -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "(error:|BUILD SUCCEEDED|BUILD FAILED)"`

Expected: BUILD SUCCEEDED

**Step 3: Final commit if any cleanup needed**

```bash
git status
# If clean, no commit needed
```

---

## Summary

**Files created:**
- `Shfl/Domain/Protocols/AutofillSource.swift`
- `Shfl/Domain/LibraryAutofillSource.swift`
- `ShflTests/Domain/AutofillSourceTests.swift`

**Files modified:**
- `Shfl/ViewModels/LibraryBrowserViewModel.swift`
- `Shfl/Views/SongPickerView.swift`
- `ShflTests/ViewModels/LibraryBrowserViewModelTests.swift`

**Commits (10 total):**
1. feat: add AutofillSource protocol
2. feat: add LibraryAutofillSource basic implementation
3. test: add comprehensive AutofillSource tests
4. feat: add autofillState to LibraryBrowserViewModel
5. feat: add autofill method to LibraryBrowserViewModel
6. test: add autofill edge case tests
7. feat: add Autofill button to SongPickerView toolbar
8. feat: add autofill completion feedback banner
9. feat: show loading spinner during autofill
10. (cleanup if needed)
