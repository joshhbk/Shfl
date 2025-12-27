# Dynamic Queue Updates - Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Keep playback queue in sync when songs are added/removed during active playback.

**Architecture:** Track played songs in ShufflePlayer; when songs change during playback, rebuild queue excluding already-played songs. MusicService gets updated queue via existing setQueue() method.

**Tech Stack:** Swift, MusicKit, XCTest

---

## Task 1: Add PlaybackState Helper Extensions

**Files:**
- Modify: `Shfl/Domain/Models/PlaybackState.swift:44` (add after existing code)
- Test: `ShflTests/Domain/PlaybackStateTests.swift`

**Step 1: Write the failing tests**

Add to `ShflTests/Domain/PlaybackStateTests.swift`:

```swift
// MARK: - isActive Tests

func testIsActive_returnsTrue_forPlayingState() {
    let song = Song(id: "1", title: "Test", artist: "Artist", albumTitle: "Album", artworkURL: nil)
    let state = PlaybackState.playing(song)
    XCTAssertTrue(state.isActive)
}

func testIsActive_returnsTrue_forPausedState() {
    let song = Song(id: "1", title: "Test", artist: "Artist", albumTitle: "Album", artworkURL: nil)
    let state = PlaybackState.paused(song)
    XCTAssertTrue(state.isActive)
}

func testIsActive_returnsTrue_forLoadingState() {
    let song = Song(id: "1", title: "Test", artist: "Artist", albumTitle: "Album", artworkURL: nil)
    let state = PlaybackState.loading(song)
    XCTAssertTrue(state.isActive)
}

func testIsActive_returnsFalse_forEmptyState() {
    let state = PlaybackState.empty
    XCTAssertFalse(state.isActive)
}

func testIsActive_returnsFalse_forStoppedState() {
    let state = PlaybackState.stopped
    XCTAssertFalse(state.isActive)
}

func testIsActive_returnsFalse_forErrorState() {
    let state = PlaybackState.error(NSError(domain: "test", code: 1))
    XCTAssertFalse(state.isActive)
}

// MARK: - currentSongId Tests

func testCurrentSongId_returnsId_forPlayingState() {
    let song = Song(id: "abc123", title: "Test", artist: "Artist", albumTitle: "Album", artworkURL: nil)
    let state = PlaybackState.playing(song)
    XCTAssertEqual(state.currentSongId, "abc123")
}

func testCurrentSongId_returnsNil_forEmptyState() {
    let state = PlaybackState.empty
    XCTAssertNil(state.currentSongId)
}

func testCurrentSongId_returnsNil_forStoppedState() {
    let state = PlaybackState.stopped
    XCTAssertNil(state.currentSongId)
}
```

**Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project Shfl.xcodeproj -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:ShflTests/PlaybackStateTests 2>&1 | grep -E "(Test Case|passed|failed|error:)"`

Expected: FAIL with "has no member 'isActive'" and "has no member 'currentSongId'"

**Step 3: Implement the helpers**

Add to end of `Shfl/Domain/Models/PlaybackState.swift`:

```swift
extension PlaybackState {
    var isActive: Bool {
        switch self {
        case .playing, .paused, .loading:
            return true
        case .empty, .stopped, .error:
            return false
        }
    }

    var currentSongId: String? {
        switch self {
        case .playing(let song), .paused(let song), .loading(let song):
            return song.id
        case .empty, .stopped, .error:
            return nil
        }
    }
}
```

**Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project Shfl.xcodeproj -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:ShflTests/PlaybackStateTests 2>&1 | grep -E "(Test Case|passed|failed|Executed)"`

Expected: All tests PASS

**Step 5: Commit**

```bash
git add Shfl/Domain/Models/PlaybackState.swift ShflTests/Domain/PlaybackStateTests.swift
git commit -m "feat: add isActive and currentSongId helpers to PlaybackState"
```

---

## Task 2: Update MockMusicService for Queue Tracking

**Files:**
- Modify: `ShflTests/Mocks/MockMusicService.swift`

**Step 1: Add tracking properties**

Add after line 10 (after `var librarySongs: [Song] = []`):

```swift
var setQueueCallCount: Int = 0
var lastQueuedSongs: [Song] = []
```

**Step 2: Update setQueue to track calls**

Replace the existing `setQueue` method:

```swift
func setQueue(songs: [Song]) async throws {
    setQueueCallCount += 1
    lastQueuedSongs = songs
    queuedSongs = songs.shuffled()
    currentIndex = 0
    if queuedSongs.isEmpty {
        updateState(.empty)
    } else {
        updateState(.stopped)
    }
}
```

**Step 3: Add reset helper for tests**

Add after `simulatePlaybackState`:

```swift
func resetQueueTracking() {
    setQueueCallCount = 0
    lastQueuedSongs = []
}
```

**Step 4: Commit**

```bash
git add ShflTests/Mocks/MockMusicService.swift
git commit -m "test: add queue tracking to MockMusicService"
```

---

## Task 3: Add History Tracking Properties to ShufflePlayer

**Files:**
- Modify: `Shfl/Domain/ShufflePlayer.swift`

**Step 1: Add the properties**

Add after line 16 (after `@Published private(set) var playbackState: PlaybackState = .empty`):

```swift
private var playedSongIds: Set<String> = []
private var lastObservedSongId: String?
```

**Step 2: Commit**

```bash
git add Shfl/Domain/ShufflePlayer.swift
git commit -m "feat: add play history tracking properties to ShufflePlayer"
```

---

## Task 4: Implement Song Transition Detection

**Files:**
- Modify: `Shfl/Domain/ShufflePlayer.swift`
- Test: `ShflTests/Domain/ShufflePlayerTests.swift`

**Step 1: Write the failing test**

Add to `ShflTests/Domain/ShufflePlayerTests.swift`:

```swift
// MARK: - Play History Tracking

func testSongTransitionAddsToHistory() async throws {
    let song1 = Song(id: "1", title: "Song 1", artist: "Artist", albumTitle: "Album", artworkURL: nil)
    let song2 = Song(id: "2", title: "Song 2", artist: "Artist", albumTitle: "Album", artworkURL: nil)
    try await player.addSong(song1)
    try await player.addSong(song2)
    try await player.play()
    try await Task.sleep(nanoseconds: 100_000_000)

    // Simulate song transition
    await mockService.simulatePlaybackState(.playing(song2))
    try await Task.sleep(nanoseconds: 100_000_000)

    let playedIds = await player.playedSongIds
    XCTAssertTrue(playedIds.contains("1"))
    XCTAssertFalse(playedIds.contains("2"))
}

func testHistoryClearedOnStop() async throws {
    let song1 = Song(id: "1", title: "Song 1", artist: "Artist", albumTitle: "Album", artworkURL: nil)
    let song2 = Song(id: "2", title: "Song 2", artist: "Artist", albumTitle: "Album", artworkURL: nil)
    try await player.addSong(song1)
    try await player.addSong(song2)
    try await player.play()
    try await Task.sleep(nanoseconds: 100_000_000)

    // Simulate song transition then stop
    await mockService.simulatePlaybackState(.playing(song2))
    try await Task.sleep(nanoseconds: 100_000_000)
    await mockService.simulatePlaybackState(.stopped)
    try await Task.sleep(nanoseconds: 100_000_000)

    let playedIds = await player.playedSongIds
    XCTAssertTrue(playedIds.isEmpty)
}

func testHistoryClearedOnEmpty() async throws {
    let song = Song(id: "1", title: "Song 1", artist: "Artist", albumTitle: "Album", artworkURL: nil)
    try await player.addSong(song)
    try await player.play()
    try await Task.sleep(nanoseconds: 100_000_000)

    await mockService.simulatePlaybackState(.empty)
    try await Task.sleep(nanoseconds: 100_000_000)

    let playedIds = await player.playedSongIds
    XCTAssertTrue(playedIds.isEmpty)
}
```

**Step 2: Expose playedSongIds for testing**

Add to `ShufflePlayer.swift` after line 23 (after `var remainingCapacity`):

```swift
#if DEBUG
var playedSongIds: Set<String> { _playedSongIds }
private var _playedSongIds: Set<String> = []
#else
private var playedSongIds: Set<String> = []
#endif
```

Wait - this is getting complicated. Let's use a simpler approach. Add a computed property:

```swift
/// Exposed for testing only
var playedSongIdsForTesting: Set<String> { playedSongIds }
```

Add after line 23.

**Step 3: Run tests to verify they fail**

Run: `xcodebuild test -project Shfl.xcodeproj -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:ShflTests/ShufflePlayerTests/testSongTransitionAddsToHistory 2>&1 | grep -E "(Test Case|passed|failed|error:)"`

Expected: FAIL

**Step 4: Implement transition detection**

Replace the `observePlaybackState` method in `ShufflePlayer.swift`:

```swift
private func observePlaybackState() {
    stateTask = Task { [weak self] in
        guard let self else { return }
        for await state in musicService.playbackStateStream {
            self.handlePlaybackStateChange(state)
        }
    }
}

private func handlePlaybackStateChange(_ newState: PlaybackState) {
    let newSongId = newState.currentSongId

    // Song changed - add previous to history
    if let lastId = lastObservedSongId, lastId != newSongId {
        playedSongIds.insert(lastId)
    }
    lastObservedSongId = newSongId

    // Clear history on stop/empty
    switch newState {
    case .stopped, .empty:
        playedSongIds.removeAll()
        lastObservedSongId = nil
    default:
        break
    }

    playbackState = newState
}
```

**Step 5: Run tests to verify they pass**

Run: `xcodebuild test -project Shfl.xcodeproj -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:ShflTests/ShufflePlayerTests 2>&1 | grep -E "(Test Case|passed|failed|Executed)"`

Expected: All tests PASS

**Step 6: Commit**

```bash
git add Shfl/Domain/ShufflePlayer.swift ShflTests/Domain/ShufflePlayerTests.swift
git commit -m "feat: track song transitions in play history"
```

---

## Task 5: Implement Queue Rebuild on Add

**Files:**
- Modify: `Shfl/Domain/ShufflePlayer.swift`
- Test: `ShflTests/Domain/ShufflePlayerTests.swift`

**Step 1: Write the failing test**

Add to `ShflTests/Domain/ShufflePlayerTests.swift`:

```swift
// MARK: - Dynamic Queue Updates

func testAddSongDuringPlaybackRebuildsQueue() async throws {
    let song1 = Song(id: "1", title: "Song 1", artist: "Artist", albumTitle: "Album", artworkURL: nil)
    try await player.addSong(song1)
    try await player.play()
    try await Task.sleep(nanoseconds: 100_000_000)

    await mockService.resetQueueTracking()

    let song2 = Song(id: "2", title: "Song 2", artist: "Artist", albumTitle: "Album", artworkURL: nil)
    try await player.addSong(song2)
    try await Task.sleep(nanoseconds: 100_000_000)

    let callCount = await mockService.setQueueCallCount
    XCTAssertEqual(callCount, 1, "setQueue should be called when adding song during playback")
}

func testAddSongWhileStoppedDoesNotRebuildQueue() async throws {
    let song1 = Song(id: "1", title: "Song 1", artist: "Artist", albumTitle: "Album", artworkURL: nil)
    try await player.addSong(song1)

    await mockService.resetQueueTracking()

    let song2 = Song(id: "2", title: "Song 2", artist: "Artist", albumTitle: "Album", artworkURL: nil)
    try await player.addSong(song2)
    try await Task.sleep(nanoseconds: 100_000_000)

    let callCount = await mockService.setQueueCallCount
    XCTAssertEqual(callCount, 0, "setQueue should NOT be called when not playing")
}

func testPlayedSongsExcludedFromRebuild() async throws {
    let song1 = Song(id: "1", title: "Song 1", artist: "Artist", albumTitle: "Album", artworkURL: nil)
    let song2 = Song(id: "2", title: "Song 2", artist: "Artist", albumTitle: "Album", artworkURL: nil)
    try await player.addSong(song1)
    try await player.addSong(song2)
    try await player.play()
    try await Task.sleep(nanoseconds: 100_000_000)

    // Simulate song1 finished, now playing song2
    await mockService.simulatePlaybackState(.playing(song2))
    try await Task.sleep(nanoseconds: 100_000_000)

    await mockService.resetQueueTracking()

    // Add new song
    let song3 = Song(id: "3", title: "Song 3", artist: "Artist", albumTitle: "Album", artworkURL: nil)
    try await player.addSong(song3)
    try await Task.sleep(nanoseconds: 100_000_000)

    let lastQueued = await mockService.lastQueuedSongs
    let queuedIds = Set(lastQueued.map { $0.id })

    XCTAssertFalse(queuedIds.contains("1"), "Played song1 should be excluded")
    XCTAssertTrue(queuedIds.contains("2"), "Current song2 should be included")
    XCTAssertTrue(queuedIds.contains("3"), "New song3 should be included")
}
```

**Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project Shfl.xcodeproj -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:ShflTests/ShufflePlayerTests/testAddSongDuringPlaybackRebuildsQueue 2>&1 | grep -E "(Test Case|passed|failed|error:)"`

Expected: FAIL

**Step 3: Implement rebuildQueueIfPlaying**

Add to `ShufflePlayer.swift` after the `handlePlaybackStateChange` method:

```swift
private func rebuildQueueIfPlaying() {
    guard playbackState.isActive else { return }

    let upcomingSongs = songs.filter { !playedSongIds.contains($0.id) }
    guard !upcomingSongs.isEmpty else { return }

    Task {
        try? await musicService.setQueue(songs: upcomingSongs)
    }
}
```

**Step 4: Update addSong to call rebuild**

Replace the `addSong` method:

```swift
func addSong(_ song: Song) throws {
    guard songs.count < Self.maxSongs else {
        throw ShufflePlayerError.capacityReached
    }
    guard !songs.contains(where: { $0.id == song.id }) else {
        return // Already added
    }
    songs.append(song)
    rebuildQueueIfPlaying()
}
```

**Step 5: Run tests to verify they pass**

Run: `xcodebuild test -project Shfl.xcodeproj -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:ShflTests/ShufflePlayerTests 2>&1 | grep -E "(Test Case|passed|failed|Executed)"`

Expected: All tests PASS

**Step 6: Commit**

```bash
git add Shfl/Domain/ShufflePlayer.swift ShflTests/Domain/ShufflePlayerTests.swift
git commit -m "feat: rebuild queue when adding songs during playback"
```

---

## Task 6: Implement Queue Rebuild on Remove

**Files:**
- Modify: `Shfl/Domain/ShufflePlayer.swift`
- Test: `ShflTests/Domain/ShufflePlayerTests.swift`

**Step 1: Write the failing test**

Add to `ShflTests/Domain/ShufflePlayerTests.swift`:

```swift
func testRemoveSongDuringPlaybackRebuildsQueue() async throws {
    let song1 = Song(id: "1", title: "Song 1", artist: "Artist", albumTitle: "Album", artworkURL: nil)
    let song2 = Song(id: "2", title: "Song 2", artist: "Artist", albumTitle: "Album", artworkURL: nil)
    try await player.addSong(song1)
    try await player.addSong(song2)
    try await player.play()
    try await Task.sleep(nanoseconds: 100_000_000)

    await mockService.resetQueueTracking()

    await player.removeSong(id: "2")
    try await Task.sleep(nanoseconds: 100_000_000)

    let callCount = await mockService.setQueueCallCount
    XCTAssertEqual(callCount, 1, "setQueue should be called when removing song during playback")

    let lastQueued = await mockService.lastQueuedSongs
    let queuedIds = lastQueued.map { $0.id }
    XCTAssertFalse(queuedIds.contains("2"), "Removed song should not be in queue")
}

func testRemoveCurrentlyPlayingSongContinuesPlayback() async throws {
    let song1 = Song(id: "1", title: "Song 1", artist: "Artist", albumTitle: "Album", artworkURL: nil)
    let song2 = Song(id: "2", title: "Song 2", artist: "Artist", albumTitle: "Album", artworkURL: nil)
    try await player.addSong(song1)
    try await player.addSong(song2)
    try await player.play()
    try await Task.sleep(nanoseconds: 100_000_000)

    // Remove currently playing song
    let currentSongId = await player.playbackState.currentSongId
    await player.removeSong(id: currentSongId!)
    try await Task.sleep(nanoseconds: 100_000_000)

    // Playback should still be active (song finishes naturally)
    let state = await player.playbackState
    XCTAssertTrue(state.isActive, "Playback should continue after removing current song")

    // Song should be removed from songs list
    let containsSong = await player.containsSong(id: currentSongId!)
    XCTAssertFalse(containsSong, "Removed song should not be in songs list")
}
```

**Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project Shfl.xcodeproj -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:ShflTests/ShufflePlayerTests/testRemoveSongDuringPlaybackRebuildsQueue 2>&1 | grep -E "(Test Case|passed|failed|error:)"`

Expected: FAIL

**Step 3: Update removeSong to call rebuild**

Replace the `removeSong` method in `ShufflePlayer.swift`:

```swift
func removeSong(id: String) {
    songs.removeAll { $0.id == id }
    rebuildQueueIfPlaying()
}
```

**Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project Shfl.xcodeproj -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:ShflTests/ShufflePlayerTests 2>&1 | grep -E "(Test Case|passed|failed|Executed)"`

Expected: All tests PASS

**Step 5: Commit**

```bash
git add Shfl/Domain/ShufflePlayer.swift ShflTests/Domain/ShufflePlayerTests.swift
git commit -m "feat: rebuild queue when removing songs during playback"
```

---

## Task 7: Clear History on Fresh Play

**Files:**
- Modify: `Shfl/Domain/ShufflePlayer.swift`
- Test: `ShflTests/Domain/ShufflePlayerTests.swift`

**Step 1: Write the failing test**

Add to `ShflTests/Domain/ShufflePlayerTests.swift`:

```swift
func testPlayClearsHistory() async throws {
    let song1 = Song(id: "1", title: "Song 1", artist: "Artist", albumTitle: "Album", artworkURL: nil)
    let song2 = Song(id: "2", title: "Song 2", artist: "Artist", albumTitle: "Album", artworkURL: nil)
    try await player.addSong(song1)
    try await player.addSong(song2)
    try await player.play()
    try await Task.sleep(nanoseconds: 100_000_000)

    // Simulate song transition to build history
    await mockService.simulatePlaybackState(.playing(song2))
    try await Task.sleep(nanoseconds: 100_000_000)

    var playedIds = await player.playedSongIdsForTesting
    XCTAssertTrue(playedIds.contains("1"), "History should contain played song")

    // Stop and play again
    await player.pause()
    try await Task.sleep(nanoseconds: 100_000_000)
    try await player.play()
    try await Task.sleep(nanoseconds: 100_000_000)

    playedIds = await player.playedSongIdsForTesting
    XCTAssertTrue(playedIds.isEmpty, "History should be cleared on fresh play")
}
```

**Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project Shfl.xcodeproj -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:ShflTests/ShufflePlayerTests/testPlayClearsHistory 2>&1 | grep -E "(Test Case|passed|failed|error:)"`

Expected: FAIL

**Step 3: Update play() to clear history**

Replace the `play` method in `ShufflePlayer.swift`:

```swift
func play() async throws {
    guard !songs.isEmpty else { return }
    playedSongIds.removeAll()
    lastObservedSongId = nil
    try await musicService.setQueue(songs: songs)
    try await musicService.play()
}
```

**Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project Shfl.xcodeproj -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:ShflTests/ShufflePlayerTests 2>&1 | grep -E "(Test Case|passed|failed|Executed)"`

Expected: All tests PASS

**Step 5: Commit**

```bash
git add Shfl/Domain/ShufflePlayer.swift ShflTests/Domain/ShufflePlayerTests.swift
git commit -m "feat: clear play history when starting fresh playback"
```

---

## Task 8: Run Full Test Suite

**Step 1: Run all tests**

Run: `xcodebuild test -project Shfl.xcodeproj -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "(Test Case|passed|failed|Executed|\*\* TEST)"`

Expected: All tests PASS

**Step 2: Fix any failures**

If any tests fail, investigate and fix before proceeding.

**Step 3: Commit any fixes**

If fixes were needed:
```bash
git add -A
git commit -m "fix: resolve test failures"
```

---

## Task 9: Manual Verification

**Step 1: Build and run the app**

Run: `open Shfl.xcodeproj` and run on simulator

**Step 2: Test scenarios**

1. Add 5 songs, start playback
2. While playing, use Autofill to add more songs
3. Verify new songs appear in rotation (skip forward several times)
4. Remove a song that isn't currently playing
5. Verify removed song doesn't play
6. Stop playback, restart - verify all songs are back in rotation

**Step 3: Document any issues found**

If issues are found, create additional tests and fixes.

---

## Summary

After completing all tasks, you will have:

1. `PlaybackState` extensions for `isActive` and `currentSongId`
2. `MockMusicService` tracking for queue updates
3. `ShufflePlayer` with:
   - `playedSongIds` tracking song history
   - `lastObservedSongId` for transition detection
   - `handlePlaybackStateChange()` updating history
   - `rebuildQueueIfPlaying()` refreshing the queue
   - `addSong()` and `removeSong()` triggering rebuilds
   - `play()` clearing history for fresh starts

The queue now stays in sync with library changes during active playback.
