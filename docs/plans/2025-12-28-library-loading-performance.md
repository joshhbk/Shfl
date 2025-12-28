# Library Loading Performance Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Eliminate startup blocking by removing library prefetch, implementing true pagination, and using MusicKit's direct search API.

**Architecture:** Remove the in-memory library cache entirely. Use `MusicLibraryRequest` with `offset` for true pagination. Replace cache-based search with `MusicLibrarySearchRequest` for direct MusicKit queries.

**Tech Stack:** Swift, MusicKit, SwiftUI

---

### Task 1: Remove prefetchLibrary from Protocol

**Files:**
- Modify: `Shfl/Domain/Protocols/MusicService.swift:22-23`

**Step 1: Remove the prefetchLibrary method from protocol**

Delete lines 22-23:

```swift
// DELETE these lines:
/// Prefetch library songs in background for faster access later
func prefetchLibrary() async
```

The protocol should go directly from `isAuthorized` to `fetchLibrarySongs`.

**Step 2: Build to verify protocol change compiles**

Run: `xcodebuild build -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet 2>&1 | grep -E "(error:|Build Failed)"`

Expected: Build errors about missing `prefetchLibrary` implementations (this is correct - we'll fix them next)

**Step 3: Commit protocol change**

```bash
git add Shfl/Domain/Protocols/MusicService.swift
git commit -m "refactor: remove prefetchLibrary from MusicService protocol"
```

---

### Task 2: Update MockMusicService (Services)

**Files:**
- Modify: `Shfl/Services/MockMusicService.swift:17`

**Step 1: Remove prefetchLibrary implementation**

Delete line 17:

```swift
// DELETE this line:
func prefetchLibrary() async {}
```

**Step 2: Commit**

```bash
git add Shfl/Services/MockMusicService.swift
git commit -m "refactor: remove prefetchLibrary from MockMusicService"
```

---

### Task 3: Update MockMusicService (Tests)

**Files:**
- Modify: `ShflTests/Mocks/MockMusicService.swift:42`

**Step 1: Remove prefetchLibrary implementation**

Delete line 42:

```swift
// DELETE this line:
func prefetchLibrary() async {}
```

**Step 2: Commit**

```bash
git add ShflTests/Mocks/MockMusicService.swift
git commit -m "refactor: remove prefetchLibrary from test MockMusicService"
```

---

### Task 4: Remove Prefetch Call from AppViewModel

**Files:**
- Modify: `Shfl/ViewModels/AppViewModel.swift:27-29`

**Step 1: Remove the prefetch Task block**

Delete lines 27-29:

```swift
// DELETE these lines:
Task {
    await musicService.prefetchLibrary()
}
```

**Step 2: Build to verify**

Run: `xcodebuild build -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet 2>&1 | grep -E "(error:|Build Failed)"`

Expected: No errors

**Step 3: Commit**

```bash
git add Shfl/ViewModels/AppViewModel.swift
git commit -m "perf: remove library prefetch from app startup"
```

---

### Task 5: Rewrite AppleMusicService - Remove Cache

**Files:**
- Modify: `Shfl/Services/AppleMusicService.swift:10-12, 45-95`

**Step 1: Remove cache properties**

Delete lines 10-12:

```swift
// DELETE these lines:
// Library cache
private var cachedLibrary: [SortOption: [Song]] = [:]
private var prefetchTask: Task<Void, Never>?
```

**Step 2: Delete prefetchLibrary method**

Delete lines 45-49:

```swift
// DELETE this entire method:
/// Prefetch library songs in background for faster access later
func prefetchLibrary() async {
    // Prefetch most common sort option
    _ = try? await fetchAllLibrarySongs(sortedBy: .mostPlayed)
}
```

**Step 3: Delete fetchAllLibrarySongs method**

Delete lines 51-95 (the entire `fetchAllLibrarySongs` private method).

**Step 4: Commit cache removal**

```bash
git add Shfl/Services/AppleMusicService.swift
git commit -m "refactor: remove library cache from AppleMusicService"
```

---

### Task 6: Implement True Pagination

**Files:**
- Modify: `Shfl/Services/AppleMusicService.swift`

**Step 1: Rewrite fetchLibrarySongs with true pagination**

Replace the existing `fetchLibrarySongs` method with:

```swift
func fetchLibrarySongs(
    sortedBy: SortOption,
    limit: Int,
    offset: Int
) async throws -> LibraryPage {
    var request = MusicLibraryRequest<MusicKit.Song>()
    request.limit = limit
    request.offset = offset

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

    let songs = response.items.map { musicKitSong in
        Song(
            id: musicKitSong.id.rawValue,
            title: musicKitSong.title,
            artist: musicKitSong.artistName,
            albumTitle: musicKitSong.albumTitle ?? "",
            artworkURL: nil
        )
    }

    // hasMore is true if we got a full page (might be more)
    let hasMore = response.items.count == limit

    return LibraryPage(songs: songs, hasMore: hasMore)
}
```

**Step 2: Build to verify**

Run: `xcodebuild build -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet 2>&1 | grep -E "(error:|Build Failed)"`

Expected: No errors

**Step 3: Commit**

```bash
git add Shfl/Services/AppleMusicService.swift
git commit -m "feat: implement true pagination for library browsing"
```

---

### Task 7: Implement Direct MusicKit Search

**Files:**
- Modify: `Shfl/Services/AppleMusicService.swift`

**Step 1: Rewrite searchLibrarySongs to use MusicLibrarySearchRequest**

Replace the existing `searchLibrarySongs` method with:

```swift
func searchLibrarySongs(query: String) async throws -> [Song] {
    var request = MusicLibrarySearchRequest(term: query, types: [MusicKit.Song.self])
    request.limit = 50

    let response = try await request.response()

    return response.songs.map { musicKitSong in
        Song(
            id: musicKitSong.id.rawValue,
            title: musicKitSong.title,
            artist: musicKitSong.artistName,
            albumTitle: musicKitSong.albumTitle ?? "",
            artworkURL: nil
        )
    }
}
```

**Step 2: Build to verify**

Run: `xcodebuild build -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet 2>&1 | grep -E "(error:|Build Failed)"`

Expected: No errors

**Step 3: Commit**

```bash
git add Shfl/Services/AppleMusicService.swift
git commit -m "feat: use MusicLibrarySearchRequest for direct library search"
```

---

### Task 8: Run All Tests

**Step 1: Run the full test suite**

Run: `xcodebuild test -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | xcpretty`

Expected: All tests pass

**Step 2: If tests fail, debug and fix**

Common issues:
- Tests that relied on cache behavior may need adjustment
- LibraryBrowserViewModelTests may need mock updates

---

### Task 9: Manual Verification

**Step 1: Build and run the app in Simulator**

Run: `open Shfl.xcodeproj` and press Cmd+R

**Step 2: Verify startup behavior**

- App should launch immediately to player view
- Persisted queue should be available to play
- No blocking spinner on startup

**Step 3: Verify library browsing**

- Open song picker
- Should see skeleton briefly, then songs load
- Scroll down - more songs should load incrementally
- Change sort order - should reset and reload

**Step 4: Verify search**

- Type a search query
- Results should appear (querying full library)
- Clear search - should return to browse view

---

### Task 10: Final Commit and Summary

**Step 1: Verify git status is clean**

Run: `git status`

Expected: Nothing to commit, working tree clean

**Step 2: View commit log**

Run: `git log --oneline -10`

Should show commits for:
- Protocol change
- MockMusicService updates (x2)
- AppViewModel prefetch removal
- Cache removal
- True pagination
- Direct search

---

## Summary of Changes

| File | Change |
|------|--------|
| `MusicService.swift` | Remove `prefetchLibrary()` from protocol |
| `MockMusicService.swift` (Services) | Remove `prefetchLibrary()` stub |
| `MockMusicService.swift` (Tests) | Remove `prefetchLibrary()` stub |
| `AppViewModel.swift` | Remove prefetch Task from `onAppear()` |
| `AppleMusicService.swift` | Remove cache, rewrite fetch/search methods |

## Expected Outcome

- **Startup:** Instant (no library fetch blocking)
- **Browse:** True pagination (50 songs per page, loads on scroll)
- **Search:** Queries entire library via MusicKit (not limited to 1000)
- **Memory:** No library cache held in memory
