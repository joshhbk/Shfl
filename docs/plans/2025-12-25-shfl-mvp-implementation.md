# Shfl MVP Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a minimal iOS music player inspired by the iPod shuffle - 120 song limit, shuffle-only playback, distraction-free listening experience.

**Architecture:** Clean Architecture with MVVM. `ShufflePlayer` handles all business logic through a `MusicService` protocol abstraction, enabling unit testing without Apple dependencies. SwiftUI views observe player state and render a tactile, device-like interface.

**Tech Stack:** Swift, SwiftUI, MusicKit (ApplicationMusicPlayer), SwiftData for persistence, XCTest for unit tests.

---

## Task 1: Xcode Project Setup

**Files:**
- Create: `Shfl.xcodeproj` (via Xcode)
- Create: `Shfl/ShflApp.swift`
- Create: `Shfl/ContentView.swift`
- Create: `Shfl/Info.plist`
- Create: `ShflTests/ShflTests.swift`

**Step 1: Create new Xcode project**

Run Xcode and create a new iOS App project:
- Product Name: `Shfl`
- Team: (your team)
- Organization Identifier: your reverse domain
- Interface: SwiftUI
- Language: Swift
- Storage: SwiftData
- Include Tests: Yes (Unit Tests only)

**Step 2: Configure MusicKit capability**

1. Select the Shfl target
2. Go to "Signing & Capabilities"
3. Click "+ Capability"
4. Add "MusicKit"

**Step 3: Add Info.plist entry for Apple Music usage**

Add to Info.plist:
```xml
<key>NSAppleMusicUsageDescription</key>
<string>Shfl needs access to your Apple Music library to play songs.</string>
```

**Step 4: Verify project builds**

Run: `xcodebuild -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 16' build`
Expected: BUILD SUCCEEDED

**Step 5: Commit initial project**

```bash
git add .
git commit -m "chore: initial Xcode project with MusicKit capability"
```

---

## Task 2: Domain Models and PlaybackState

**Files:**
- Create: `Shfl/Domain/Models/Song.swift`
- Create: `Shfl/Domain/Models/PlaybackState.swift`
- Create: `ShflTests/Domain/PlaybackStateTests.swift`

**Step 1: Write failing test for Song model**

```swift
// ShflTests/Domain/SongTests.swift
import XCTest
@testable import Shfl

final class SongTests: XCTestCase {
    func testSongInitialization() {
        let song = Song(
            id: "12345",
            title: "Test Song",
            artist: "Test Artist",
            albumTitle: "Test Album",
            artworkURL: nil
        )

        XCTAssertEqual(song.id, "12345")
        XCTAssertEqual(song.title, "Test Song")
        XCTAssertEqual(song.artist, "Test Artist")
        XCTAssertEqual(song.albumTitle, "Test Album")
        XCTAssertNil(song.artworkURL)
    }

    func testSongEquatable() {
        let song1 = Song(id: "123", title: "A", artist: "B", albumTitle: "C", artworkURL: nil)
        let song2 = Song(id: "123", title: "A", artist: "B", albumTitle: "C", artworkURL: nil)
        let song3 = Song(id: "456", title: "A", artist: "B", albumTitle: "C", artworkURL: nil)

        XCTAssertEqual(song1, song2)
        XCTAssertNotEqual(song1, song3)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:ShflTests/SongTests`
Expected: FAIL - "Cannot find 'Song' in scope"

**Step 3: Implement Song model**

```swift
// Shfl/Domain/Models/Song.swift
import Foundation

struct Song: Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let artist: String
    let albumTitle: String
    let artworkURL: URL?
}
```

**Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:ShflTests/SongTests`
Expected: PASS

**Step 5: Write failing test for PlaybackState**

```swift
// ShflTests/Domain/PlaybackStateTests.swift
import XCTest
@testable import Shfl

final class PlaybackStateTests: XCTestCase {
    func testEmptyState() {
        let state = PlaybackState.empty
        XCTAssertTrue(state.isEmpty)
        XCTAssertNil(state.currentSong)
        XCTAssertFalse(state.isPlaying)
    }

    func testStoppedState() {
        let state = PlaybackState.stopped
        XCTAssertFalse(state.isEmpty)
        XCTAssertNil(state.currentSong)
        XCTAssertFalse(state.isPlaying)
    }

    func testPlayingState() {
        let song = Song(id: "1", title: "Test", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        let state = PlaybackState.playing(song)

        XCTAssertFalse(state.isEmpty)
        XCTAssertEqual(state.currentSong, song)
        XCTAssertTrue(state.isPlaying)
    }

    func testPausedState() {
        let song = Song(id: "1", title: "Test", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        let state = PlaybackState.paused(song)

        XCTAssertFalse(state.isEmpty)
        XCTAssertEqual(state.currentSong, song)
        XCTAssertFalse(state.isPlaying)
    }

    func testLoadingState() {
        let song = Song(id: "1", title: "Test", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        let state = PlaybackState.loading(song)

        XCTAssertEqual(state.currentSong, song)
        XCTAssertFalse(state.isPlaying)
    }

    func testErrorState() {
        let error = NSError(domain: "test", code: 1)
        let state = PlaybackState.error(error)

        XCTAssertNil(state.currentSong)
        XCTAssertFalse(state.isPlaying)
    }
}
```

**Step 6: Run test to verify it fails**

Run: `xcodebuild test -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:ShflTests/PlaybackStateTests`
Expected: FAIL - "Cannot find 'PlaybackState' in scope"

**Step 7: Implement PlaybackState enum**

```swift
// Shfl/Domain/Models/PlaybackState.swift
import Foundation

enum PlaybackState: Equatable {
    case empty
    case stopped
    case loading(Song)
    case playing(Song)
    case paused(Song)
    case error(Error)

    var isEmpty: Bool {
        if case .empty = self { return true }
        return false
    }

    var currentSong: Song? {
        switch self {
        case .loading(let song), .playing(let song), .paused(let song):
            return song
        case .empty, .stopped, .error:
            return nil
        }
    }

    var isPlaying: Bool {
        if case .playing = self { return true }
        return false
    }

    static func == (lhs: PlaybackState, rhs: PlaybackState) -> Bool {
        switch (lhs, rhs) {
        case (.empty, .empty), (.stopped, .stopped):
            return true
        case (.loading(let l), .loading(let r)),
             (.playing(let l), .playing(let r)),
             (.paused(let l), .paused(let r)):
            return l == r
        case (.error(let l), .error(let r)):
            return l.localizedDescription == r.localizedDescription
        default:
            return false
        }
    }
}
```

**Step 8: Run test to verify it passes**

Run: `xcodebuild test -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:ShflTests/PlaybackStateTests`
Expected: PASS

**Step 9: Commit**

```bash
git add .
git commit -m "feat: add Song and PlaybackState domain models"
```

---

## Task 3: MusicService Protocol

**Files:**
- Create: `Shfl/Domain/Protocols/MusicService.swift`
- Create: `ShflTests/Mocks/MockMusicService.swift`

**Step 1: Define MusicService protocol**

```swift
// Shfl/Domain/Protocols/MusicService.swift
import Foundation

protocol MusicService: Sendable {
    /// Request authorization to access Apple Music
    func requestAuthorization() async -> Bool

    /// Check current authorization status
    var isAuthorized: Bool { get async }

    /// Search for songs in user's library
    func searchLibrary(query: String) async throws -> [Song]

    /// Set the playback queue with songs and shuffle them
    func setQueue(songs: [Song]) async throws

    /// Start playback
    func play() async throws

    /// Pause playback
    func pause() async

    /// Skip to next song
    func skipToNext() async throws

    /// Get current playback state (observable)
    var playbackStateStream: AsyncStream<PlaybackState> { get }
}
```

**Step 2: Create MockMusicService for testing**

```swift
// ShflTests/Mocks/MockMusicService.swift
import Foundation
@testable import Shfl

actor MockMusicService: MusicService {
    var authorizationResult: Bool = true
    var searchResults: [Song] = []
    var shouldThrowOnPlay: Error?
    var shouldThrowOnSearch: Error?
    var shouldThrowOnSkip: Error?

    private var currentState: PlaybackState = .empty
    private var continuation: AsyncStream<PlaybackState>.Continuation?
    private var queuedSongs: [Song] = []
    private var currentIndex: Int = 0

    nonisolated var playbackStateStream: AsyncStream<PlaybackState> {
        AsyncStream { continuation in
            Task { await self.setContinuation(continuation) }
        }
    }

    private func setContinuation(_ cont: AsyncStream<PlaybackState>.Continuation) {
        self.continuation = cont
        cont.yield(currentState)
    }

    func requestAuthorization() async -> Bool {
        authorizationResult
    }

    var isAuthorized: Bool {
        authorizationResult
    }

    func searchLibrary(query: String) async throws -> [Song] {
        if let error = shouldThrowOnSearch {
            throw error
        }
        return searchResults.filter {
            $0.title.localizedCaseInsensitiveContains(query) ||
            $0.artist.localizedCaseInsensitiveContains(query)
        }
    }

    func setQueue(songs: [Song]) async throws {
        queuedSongs = songs.shuffled()
        currentIndex = 0
        if queuedSongs.isEmpty {
            updateState(.empty)
        } else {
            updateState(.stopped)
        }
    }

    func play() async throws {
        if let error = shouldThrowOnPlay {
            throw error
        }
        guard !queuedSongs.isEmpty else { return }
        let song = queuedSongs[currentIndex]
        updateState(.playing(song))
    }

    func pause() async {
        if case .playing(let song) = currentState {
            updateState(.paused(song))
        }
    }

    func skipToNext() async throws {
        if let error = shouldThrowOnSkip {
            throw error
        }
        guard !queuedSongs.isEmpty else { return }
        currentIndex = (currentIndex + 1) % queuedSongs.count
        let song = queuedSongs[currentIndex]
        updateState(.playing(song))
    }

    private func updateState(_ state: PlaybackState) {
        currentState = state
        continuation?.yield(state)
    }

    // Test helpers
    func setSearchResults(_ songs: [Song]) {
        searchResults = songs
    }

    func simulatePlaybackState(_ state: PlaybackState) {
        updateState(state)
    }
}
```

**Step 3: Verify compilation**

Run: `xcodebuild test -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 16' build-for-testing`
Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add .
git commit -m "feat: add MusicService protocol and MockMusicService"
```

---

## Task 4: ShufflePlayer Core Logic

**Files:**
- Create: `Shfl/Domain/ShufflePlayer.swift`
- Create: `ShflTests/Domain/ShufflePlayerTests.swift`

**Step 1: Write failing tests for ShufflePlayer**

```swift
// ShflTests/Domain/ShufflePlayerTests.swift
import XCTest
@testable import Shfl

final class ShufflePlayerTests: XCTestCase {
    var mockService: MockMusicService!
    var player: ShufflePlayer!

    override func setUp() async throws {
        mockService = MockMusicService()
        player = await ShufflePlayer(musicService: mockService)
    }

    // MARK: - Song Management

    func testInitialStateIsEmpty() async {
        let songCount = await player.songCount
        XCTAssertEqual(songCount, 0)
    }

    func testAddSong() async throws {
        let song = Song(id: "1", title: "Test", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        try await player.addSong(song)

        let songCount = await player.songCount
        XCTAssertEqual(songCount, 1)
    }

    func testAddSongRespectsLimit() async throws {
        for i in 0..<120 {
            let song = Song(id: "\(i)", title: "Song \(i)", artist: "Artist", albumTitle: "Album", artworkURL: nil)
            try await player.addSong(song)
        }

        let extraSong = Song(id: "extra", title: "Extra", artist: "Artist", albumTitle: "Album", artworkURL: nil)

        do {
            try await player.addSong(extraSong)
            XCTFail("Should have thrown capacity error")
        } catch ShufflePlayerError.capacityReached {
            // Expected
        }

        let songCount = await player.songCount
        XCTAssertEqual(songCount, 120)
    }

    func testRemoveSong() async throws {
        let song = Song(id: "1", title: "Test", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        try await player.addSong(song)
        await player.removeSong(id: "1")

        let songCount = await player.songCount
        XCTAssertEqual(songCount, 0)
    }

    func testRemoveAllSongs() async throws {
        for i in 0..<5 {
            let song = Song(id: "\(i)", title: "Song \(i)", artist: "Artist", albumTitle: "Album", artworkURL: nil)
            try await player.addSong(song)
        }

        await player.removeAllSongs()

        let songCount = await player.songCount
        XCTAssertEqual(songCount, 0)
    }

    // MARK: - Playback

    func testPlayWithNoSongsDoesNothing() async throws {
        try await player.play()
        // Should not crash, state remains empty
    }

    func testPlayStartsPlayback() async throws {
        let song = Song(id: "1", title: "Test", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        try await player.addSong(song)
        try await player.play()

        // Give async stream time to update
        try await Task.sleep(nanoseconds: 100_000_000)

        let state = await player.playbackState
        XCTAssertTrue(state.isPlaying)
    }

    func testPause() async throws {
        let song = Song(id: "1", title: "Test", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        try await player.addSong(song)
        try await player.play()
        try await Task.sleep(nanoseconds: 100_000_000)
        await player.pause()
        try await Task.sleep(nanoseconds: 100_000_000)

        let state = await player.playbackState
        if case .paused = state {
            // Expected
        } else {
            XCTFail("Expected paused state, got \(state)")
        }
    }

    func testSkipToNext() async throws {
        let song1 = Song(id: "1", title: "Song 1", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        let song2 = Song(id: "2", title: "Song 2", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        try await player.addSong(song1)
        try await player.addSong(song2)
        try await player.play()
        try await Task.sleep(nanoseconds: 100_000_000)
        try await player.skipToNext()
        try await Task.sleep(nanoseconds: 100_000_000)

        let state = await player.playbackState
        XCTAssertTrue(state.isPlaying)
    }

    func testTogglePlayback() async throws {
        let song = Song(id: "1", title: "Test", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        try await player.addSong(song)

        // First toggle starts playback
        try await player.togglePlayback()
        try await Task.sleep(nanoseconds: 100_000_000)
        var state = await player.playbackState
        XCTAssertTrue(state.isPlaying)

        // Second toggle pauses
        try await player.togglePlayback()
        try await Task.sleep(nanoseconds: 100_000_000)
        state = await player.playbackState
        if case .paused = state {
            // Expected
        } else {
            XCTFail("Expected paused state")
        }

        // Third toggle resumes
        try await player.togglePlayback()
        try await Task.sleep(nanoseconds: 100_000_000)
        state = await player.playbackState
        XCTAssertTrue(state.isPlaying)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:ShflTests/ShufflePlayerTests`
Expected: FAIL - "Cannot find 'ShufflePlayer' in scope"

**Step 3: Implement ShufflePlayer**

```swift
// Shfl/Domain/ShufflePlayer.swift
import Foundation

enum ShufflePlayerError: Error, Equatable {
    case capacityReached
    case notAuthorized
    case playbackFailed(String)
}

@MainActor
final class ShufflePlayer: ObservableObject {
    static let maxSongs = 120

    private let musicService: MusicService
    private var songs: [Song] = []
    private var stateTask: Task<Void, Never>?

    @Published private(set) var playbackState: PlaybackState = .empty

    var songCount: Int { songs.count }
    var allSongs: [Song] { songs }
    var capacity: Int { Self.maxSongs }
    var remainingCapacity: Int { Self.maxSongs - songs.count }

    init(musicService: MusicService) {
        self.musicService = musicService
        observePlaybackState()
    }

    deinit {
        stateTask?.cancel()
    }

    private func observePlaybackState() {
        stateTask = Task { [weak self] in
            guard let self else { return }
            for await state in musicService.playbackStateStream {
                self.playbackState = state
            }
        }
    }

    // MARK: - Song Management

    func addSong(_ song: Song) throws {
        guard songs.count < Self.maxSongs else {
            throw ShufflePlayerError.capacityReached
        }
        guard !songs.contains(where: { $0.id == song.id }) else {
            return // Already added
        }
        songs.append(song)
    }

    func removeSong(id: String) {
        songs.removeAll { $0.id == id }
    }

    func removeAllSongs() {
        songs.removeAll()
    }

    func containsSong(id: String) -> Bool {
        songs.contains { $0.id == id }
    }

    // MARK: - Playback Control

    func play() async throws {
        guard !songs.isEmpty else { return }
        try await musicService.setQueue(songs: songs)
        try await musicService.play()
    }

    func pause() async {
        await musicService.pause()
    }

    func skipToNext() async throws {
        try await musicService.skipToNext()
    }

    func togglePlayback() async throws {
        switch playbackState {
        case .empty, .stopped:
            try await play()
        case .playing:
            await pause()
        case .paused:
            try await musicService.play()
        case .loading:
            // Do nothing while loading
            break
        case .error:
            // Try to play again
            try await play()
        }
    }
}
```

**Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:ShflTests/ShufflePlayerTests`
Expected: PASS (all tests)

**Step 5: Commit**

```bash
git add .
git commit -m "feat: add ShufflePlayer with song management and playback control"
```

---

## Task 5: AppleMusicService Implementation

**Files:**
- Create: `Shfl/Services/AppleMusicService.swift`
- Create: `ShflTests/Services/AppleMusicServiceTests.swift`

**Step 1: Implement AppleMusicService**

```swift
// Shfl/Services/AppleMusicService.swift
import Foundation
import MusicKit

final class AppleMusicService: MusicService, @unchecked Sendable {
    private let player = ApplicationMusicPlayer.shared
    private var stateObservationTask: Task<Void, Never>?
    private var continuation: AsyncStream<PlaybackState>.Continuation?

    var playbackStateStream: AsyncStream<PlaybackState> {
        AsyncStream { [weak self] continuation in
            self?.continuation = continuation
            self?.startObservingPlaybackState()
        }
    }

    var isAuthorized: Bool {
        get async {
            MusicAuthorization.currentStatus == .authorized
        }
    }

    func requestAuthorization() async -> Bool {
        let status = await MusicAuthorization.request()
        return status == .authorized
    }

    func searchLibrary(query: String) async throws -> [Song] {
        var request = MusicLibraryRequest<MusicKit.Song>()
        request.filter(matching: \.title, contains: query)

        let response = try await request.response()
        return response.items.map { musicKitSong in
            Song(
                id: musicKitSong.id.rawValue,
                title: musicKitSong.title,
                artist: musicKitSong.artistName,
                albumTitle: musicKitSong.albumTitle ?? "",
                artworkURL: musicKitSong.artwork?.url(width: 300, height: 300)
            )
        }
    }

    func setQueue(songs: [Song]) async throws {
        // Convert our Song models back to MusicKit songs
        let ids = songs.map { MusicItemID($0.id) }
        var request = MusicCatalogResourceRequest<MusicKit.Song>(matching: \.id, memberOf: ids)
        let response = try await request.response()

        let queue = ApplicationMusicPlayer.Queue(for: response.items, startingAt: nil)
        player.queue = queue
        player.state.shuffleMode = .songs
    }

    func play() async throws {
        try await player.play()
    }

    func pause() async {
        player.pause()
    }

    func skipToNext() async throws {
        try await player.skipToNextEntry()
    }

    private func startObservingPlaybackState() {
        stateObservationTask?.cancel()
        stateObservationTask = Task { [weak self] in
            guard let self else { return }

            // Initial state
            self.emitCurrentState()

            // Observe state changes
            for await _ in self.player.state.objectWillChange.values {
                self.emitCurrentState()
            }
        }
    }

    private func emitCurrentState() {
        let state = mapPlaybackState()
        continuation?.yield(state)
    }

    private func mapPlaybackState() -> PlaybackState {
        guard let currentEntry = player.queue.currentEntry else {
            return .empty
        }

        guard case .song(let musicKitSong) = currentEntry.item else {
            return .stopped
        }

        let song = Song(
            id: musicKitSong.id.rawValue,
            title: musicKitSong.title,
            artist: musicKitSong.artistName,
            albumTitle: musicKitSong.albumTitle ?? "",
            artworkURL: musicKitSong.artwork?.url(width: 300, height: 300)
        )

        switch player.state.playbackStatus {
        case .playing:
            return .playing(song)
        case .paused:
            return .paused(song)
        case .stopped:
            return .stopped
        case .interrupted:
            return .paused(song)
        case .seekingForward, .seekingBackward:
            return .playing(song)
        @unknown default:
            return .stopped
        }
    }
}
```

**Step 2: Verify compilation (no runtime tests for MusicKit)**

Run: `xcodebuild -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 16' build`
Expected: BUILD SUCCEEDED

Note: MusicKit requires actual device and Apple Music subscription to test. Unit tests use MockMusicService.

**Step 3: Commit**

```bash
git add .
git commit -m "feat: add AppleMusicService implementation"
```

---

## Task 6: Persistence Layer with SwiftData

**Files:**
- Create: `Shfl/Data/Models/PersistedSong.swift`
- Create: `Shfl/Data/SongRepository.swift`
- Create: `ShflTests/Data/SongRepositoryTests.swift`

**Step 1: Write failing test for SongRepository**

```swift
// ShflTests/Data/SongRepositoryTests.swift
import XCTest
import SwiftData
@testable import Shfl

final class SongRepositoryTests: XCTestCase {
    var container: ModelContainer!
    var repository: SongRepository!

    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: PersistedSong.self, configurations: config)
        repository = SongRepository(modelContext: container.mainContext)
    }

    override func tearDown() {
        container = nil
        repository = nil
    }

    func testSaveAndLoadSongs() async throws {
        let songs = [
            Song(id: "1", title: "Song 1", artist: "Artist 1", albumTitle: "Album 1", artworkURL: nil),
            Song(id: "2", title: "Song 2", artist: "Artist 2", albumTitle: "Album 2", artworkURL: nil)
        ]

        try await repository.saveSongs(songs)
        let loaded = try await repository.loadSongs()

        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded[0].id, "1")
        XCTAssertEqual(loaded[1].id, "2")
    }

    func testSaveSongReplacesExisting() async throws {
        let songs1 = [Song(id: "1", title: "Original", artist: "A", albumTitle: "B", artworkURL: nil)]
        try await repository.saveSongs(songs1)

        let songs2 = [Song(id: "2", title: "New", artist: "C", albumTitle: "D", artworkURL: nil)]
        try await repository.saveSongs(songs2)

        let loaded = try await repository.loadSongs()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].id, "2")
    }

    func testClearSongs() async throws {
        let songs = [Song(id: "1", title: "Song", artist: "A", albumTitle: "B", artworkURL: nil)]
        try await repository.saveSongs(songs)
        try await repository.clearSongs()

        let loaded = try await repository.loadSongs()
        XCTAssertTrue(loaded.isEmpty)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:ShflTests/SongRepositoryTests`
Expected: FAIL - Cannot find types

**Step 3: Implement PersistedSong model**

```swift
// Shfl/Data/Models/PersistedSong.swift
import Foundation
import SwiftData

@Model
final class PersistedSong {
    @Attribute(.unique) var songId: String
    var title: String
    var artist: String
    var albumTitle: String
    var artworkURLString: String?
    var orderIndex: Int

    init(songId: String, title: String, artist: String, albumTitle: String, artworkURLString: String?, orderIndex: Int) {
        self.songId = songId
        self.title = title
        self.artist = artist
        self.albumTitle = albumTitle
        self.artworkURLString = artworkURLString
        self.orderIndex = orderIndex
    }

    func toSong() -> Song {
        Song(
            id: songId,
            title: title,
            artist: artist,
            albumTitle: albumTitle,
            artworkURL: artworkURLString.flatMap { URL(string: $0) }
        )
    }

    static func from(_ song: Song, orderIndex: Int) -> PersistedSong {
        PersistedSong(
            songId: song.id,
            title: song.title,
            artist: song.artist,
            albumTitle: song.albumTitle,
            artworkURLString: song.artworkURL?.absoluteString,
            orderIndex: orderIndex
        )
    }
}
```

**Step 4: Implement SongRepository**

```swift
// Shfl/Data/SongRepository.swift
import Foundation
import SwiftData

@MainActor
final class SongRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func saveSongs(_ songs: [Song]) throws {
        // Clear existing
        try clearSongs()

        // Insert new
        for (index, song) in songs.enumerated() {
            let persisted = PersistedSong.from(song, orderIndex: index)
            modelContext.insert(persisted)
        }

        try modelContext.save()
    }

    func loadSongs() throws -> [Song] {
        let descriptor = FetchDescriptor<PersistedSong>(
            sortBy: [SortDescriptor(\.orderIndex)]
        )
        let persisted = try modelContext.fetch(descriptor)
        return persisted.map { $0.toSong() }
    }

    func clearSongs() throws {
        try modelContext.delete(model: PersistedSong.self)
    }
}
```

**Step 5: Update ShflApp to include SwiftData container**

```swift
// Shfl/ShflApp.swift
import SwiftUI
import SwiftData

@main
struct ShflApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([PersistedSong.self])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
```

**Step 6: Run tests to verify they pass**

Run: `xcodebuild test -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:ShflTests/SongRepositoryTests`
Expected: PASS

**Step 7: Commit**

```bash
git add .
git commit -m "feat: add SwiftData persistence with SongRepository"
```

---

## Task 7: Main Player View

**Files:**
- Modify: `Shfl/ContentView.swift` -> `Shfl/Views/PlayerView.swift`
- Create: `Shfl/Views/Components/PlayPauseButton.swift`
- Create: `Shfl/Views/Components/SkipButton.swift`
- Create: `Shfl/Views/Components/CapacityIndicator.swift`
- Create: `Shfl/Views/Components/NowPlayingInfo.swift`

**Step 1: Create PlayPauseButton component**

```swift
// Shfl/Views/Components/PlayPauseButton.swift
import SwiftUI

struct PlayPauseButton: View {
    let isPlaying: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(.white)
                    .frame(width: 80, height: 80)
                    .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)

                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(.black)
                    .offset(x: isPlaying ? 0 : 2)
            }
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .medium), trigger: isPlaying)
    }
}

#Preview {
    VStack(spacing: 40) {
        PlayPauseButton(isPlaying: false) {}
        PlayPauseButton(isPlaying: true) {}
    }
    .padding()
    .background(Color.gray.opacity(0.2))
}
```

**Step 2: Create SkipButton component**

```swift
// Shfl/Views/Components/SkipButton.swift
import SwiftUI

struct SkipButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.9))
                    .frame(width: 56, height: 56)
                    .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)

                Image(systemName: "forward.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.black.opacity(0.8))
            }
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .light), trigger: UUID())
    }
}

#Preview {
    SkipButton {}
        .padding()
        .background(Color.gray.opacity(0.2))
}
```

**Step 3: Create CapacityIndicator component**

```swift
// Shfl/Views/Components/CapacityIndicator.swift
import SwiftUI

struct CapacityIndicator: View {
    let current: Int
    let maximum: Int

    var body: some View {
        Text("\(current)/\(maximum)")
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
            )
    }
}

#Preview {
    VStack(spacing: 20) {
        CapacityIndicator(current: 0, maximum: 120)
        CapacityIndicator(current: 47, maximum: 120)
        CapacityIndicator(current: 120, maximum: 120)
    }
    .padding()
}
```

**Step 4: Create NowPlayingInfo component**

```swift
// Shfl/Views/Components/NowPlayingInfo.swift
import SwiftUI

struct NowPlayingInfo: View {
    let title: String
    let artist: String

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text(artist)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    NowPlayingInfo(title: "Bohemian Rhapsody", artist: "Queen")
        .padding()
}
```

**Step 5: Create PlayerView**

```swift
// Shfl/Views/PlayerView.swift
import SwiftUI

struct PlayerView: View {
    @ObservedObject var player: ShufflePlayer
    let onManageTapped: () -> Void

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                backgroundGradient

                VStack(spacing: 0) {
                    // Top section: Capacity indicator
                    HStack {
                        Spacer()
                        CapacityIndicator(current: player.songCount, maximum: player.capacity)
                        Spacer()
                    }
                    .padding(.top, geometry.safeAreaInsets.top + 16)

                    Spacer()

                    // Center section: Now playing info + controls
                    VStack(spacing: 48) {
                        // Now playing info
                        if let song = player.playbackState.currentSong {
                            NowPlayingInfo(title: song.title, artist: song.artist)
                                .transition(.opacity)
                        } else {
                            emptyStateView
                        }

                        // Controls
                        controlsSection
                    }
                    .padding(.horizontal, 32)

                    Spacer()

                    // Bottom section: Manage button
                    Button(action: onManageTapped) {
                        Text("Manage Songs")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, geometry.safeAreaInsets.bottom + 24)
                }
            }
            .ignoresSafeArea()
        }
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(white: 0.95),
                Color(white: 0.90)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Text("No songs yet")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)

            Text("Add some music to get started")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
    }

    private var controlsSection: some View {
        HStack(spacing: 40) {
            // Skip button (only visible when songs exist)
            if player.songCount > 0 {
                SkipButton {
                    Task {
                        try? await player.skipToNext()
                    }
                }
            } else {
                Color.clear.frame(width: 56, height: 56)
            }

            // Play/Pause button
            PlayPauseButton(isPlaying: player.playbackState.isPlaying) {
                Task {
                    try? await player.togglePlayback()
                }
            }
            .disabled(player.songCount == 0)
            .opacity(player.songCount == 0 ? 0.5 : 1.0)

            // Spacer for symmetry
            Color.clear.frame(width: 56, height: 56)
        }
    }
}

#Preview("Empty State") {
    let mockService = PreviewMockMusicService()
    let player = ShufflePlayer(musicService: mockService)
    return PlayerView(player: player, onManageTapped: {})
}

#Preview("Playing") {
    let mockService = PreviewMockMusicService()
    let player = ShufflePlayer(musicService: mockService)

    // Add songs and simulate playing state would be done here
    return PlayerView(player: player, onManageTapped: {})
}

// Preview helper
private final class PreviewMockMusicService: MusicService, @unchecked Sendable {
    var isAuthorized: Bool { true }
    var playbackStateStream: AsyncStream<PlaybackState> {
        AsyncStream { continuation in
            continuation.yield(.empty)
        }
    }
    func requestAuthorization() async -> Bool { true }
    func searchLibrary(query: String) async throws -> [Song] { [] }
    func setQueue(songs: [Song]) async throws {}
    func play() async throws {}
    func pause() async {}
    func skipToNext() async throws {}
}
```

**Step 6: Verify UI builds**

Run: `xcodebuild -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 16' build`
Expected: BUILD SUCCEEDED

**Step 7: Commit**

```bash
git add .
git commit -m "feat: add PlayerView with playback controls"
```

---

## Task 8: Song Picker View

**Files:**
- Create: `Shfl/Views/SongPickerView.swift`
- Create: `Shfl/Views/Components/SongRow.swift`
- Create: `Shfl/Views/ManageView.swift`

**Step 1: Create SongRow component**

```swift
// Shfl/Views/Components/SongRow.swift
import SwiftUI

struct SongRow: View {
    let song: Song
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                // Artwork placeholder
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 44, height: 44)
                    .overlay {
                        if let url = song.artworkURL {
                            AsyncImage(url: url) { image in
                                image.resizable().aspectRatio(contentMode: .fill)
                            } placeholder: {
                                Image(systemName: "music.note")
                                    .foregroundStyle(.gray)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        } else {
                            Image(systemName: "music.note")
                                .foregroundStyle(.gray)
                        }
                    }

                // Song info
                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(song.artist)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                // Selection indicator
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isSelected ? .blue : .gray.opacity(0.4))
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    VStack(spacing: 0) {
        SongRow(
            song: Song(id: "1", title: "Bohemian Rhapsody", artist: "Queen", albumTitle: "A Night at the Opera", artworkURL: nil),
            isSelected: false,
            onToggle: {}
        )
        Divider()
        SongRow(
            song: Song(id: "2", title: "Stairway to Heaven", artist: "Led Zeppelin", albumTitle: "Led Zeppelin IV", artworkURL: nil),
            isSelected: true,
            onToggle: {}
        )
    }
}
```

**Step 2: Create SongPickerView**

```swift
// Shfl/Views/SongPickerView.swift
import SwiftUI

struct SongPickerView: View {
    @ObservedObject var player: ShufflePlayer
    let musicService: MusicService
    let onDismiss: () -> Void

    @State private var searchText = ""
    @State private var searchResults: [Song] = []
    @State private var isSearching = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Capacity bar
                capacityBar

                // Search results
                if isSearching {
                    ProgressView("Searching...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if searchResults.isEmpty && !searchText.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else if searchResults.isEmpty {
                    ContentUnavailableView(
                        "Search Your Library",
                        systemImage: "magnifyingglass",
                        description: Text("Type to search your Apple Music library")
                    )
                } else {
                    songList
                }
            }
            .navigationTitle("Add Songs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDismiss)
                }
            }
            .searchable(text: $searchText, prompt: "Search your library")
            .onChange(of: searchText) { _, newValue in
                performSearch(query: newValue)
            }
            .alert("Error", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                if let error = errorMessage {
                    Text(error)
                }
            }
        }
    }

    private var capacityBar: some View {
        HStack {
            Text("\(player.songCount) of \(player.capacity) songs")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            Spacer()

            if player.remainingCapacity == 0 {
                Text("Full")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.systemGroupedBackground))
    }

    private var songList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(searchResults) { song in
                    SongRow(
                        song: song,
                        isSelected: player.containsSong(id: song.id),
                        onToggle: { toggleSong(song) }
                    )
                    Divider()
                        .padding(.leading, 72)
                }
            }
        }
    }

    private func performSearch(query: String) {
        guard !query.isEmpty else {
            searchResults = []
            return
        }

        isSearching = true
        Task {
            do {
                let results = try await musicService.searchLibrary(query: query)
                await MainActor.run {
                    searchResults = results
                    isSearching = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isSearching = false
                }
            }
        }
    }

    private func toggleSong(_ song: Song) {
        if player.containsSong(id: song.id) {
            player.removeSong(id: song.id)
        } else {
            do {
                try player.addSong(song)
            } catch ShufflePlayerError.capacityReached {
                errorMessage = "You've reached the maximum of \(player.capacity) songs"
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
```

**Step 3: Create ManageView**

```swift
// Shfl/Views/ManageView.swift
import SwiftUI

struct ManageView: View {
    @ObservedObject var player: ShufflePlayer
    let onAddTapped: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                if player.allSongs.isEmpty {
                    emptyState
                } else {
                    songList
                }
            }
            .navigationTitle("Your Songs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", action: onDismiss)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        onAddTapped()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(player.remainingCapacity == 0)
                }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Songs", systemImage: "music.note")
        } description: {
            Text("Add songs from your Apple Music library to start shuffling")
        } actions: {
            Button("Add Songs", action: onAddTapped)
                .buttonStyle(.borderedProminent)
        }
    }

    private var songList: some View {
        List {
            Section {
                ForEach(player.allSongs) { song in
                    HStack(spacing: 12) {
                        // Artwork
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 44, height: 44)
                            .overlay {
                                if let url = song.artworkURL {
                                    AsyncImage(url: url) { image in
                                        image.resizable().aspectRatio(contentMode: .fill)
                                    } placeholder: {
                                        Image(systemName: "music.note")
                                            .foregroundStyle(.gray)
                                    }
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                } else {
                                    Image(systemName: "music.note")
                                        .foregroundStyle(.gray)
                                }
                            }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(song.title)
                                .font(.system(size: 16, weight: .medium))
                                .lineLimit(1)

                            Text(song.artist)
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            player.removeSong(id: song.id)
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                }
            } header: {
                Text("\(player.songCount) of \(player.capacity) songs")
            }
        }
    }
}
```

**Step 4: Verify UI builds**

Run: `xcodebuild -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 16' build`
Expected: BUILD SUCCEEDED

**Step 5: Commit**

```bash
git add .
git commit -m "feat: add SongPickerView and ManageView"
```

---

## Task 9: Main App Coordinator

**Files:**
- Create: `Shfl/Views/MainView.swift`
- Modify: `Shfl/ShflApp.swift`
- Create: `Shfl/ViewModels/AppViewModel.swift`

**Step 1: Create AppViewModel**

```swift
// Shfl/ViewModels/AppViewModel.swift
import SwiftUI
import SwiftData

@MainActor
final class AppViewModel: ObservableObject {
    let player: ShufflePlayer
    let musicService: MusicService
    private let repository: SongRepository

    @Published var isAuthorized = false
    @Published var showingManage = false
    @Published var showingPicker = false
    @Published var authorizationError: String?

    init(musicService: MusicService, modelContext: ModelContext) {
        self.musicService = musicService
        self.player = ShufflePlayer(musicService: musicService)
        self.repository = SongRepository(modelContext: modelContext)
    }

    func onAppear() async {
        // Check authorization
        isAuthorized = await musicService.isAuthorized

        // Load persisted songs
        do {
            let songs = try repository.loadSongs()
            for song in songs {
                try? player.addSong(song)
            }
        } catch {
            print("Failed to load songs: \(error)")
        }
    }

    func requestAuthorization() async {
        isAuthorized = await musicService.requestAuthorization()
        if !isAuthorized {
            authorizationError = "Apple Music access is required to use Shfl. Please enable it in Settings."
        }
    }

    func persistSongs() {
        do {
            try repository.saveSongs(player.allSongs)
        } catch {
            print("Failed to save songs: \(error)")
        }
    }

    func openManage() {
        showingManage = true
    }

    func closeManage() {
        showingManage = false
        persistSongs()
    }

    func openPicker() {
        showingPicker = true
    }

    func closePicker() {
        showingPicker = false
        persistSongs()
    }
}
```

**Step 2: Create MainView**

```swift
// Shfl/Views/MainView.swift
import SwiftUI

struct MainView: View {
    @StateObject private var viewModel: AppViewModel

    init(musicService: MusicService, modelContext: SwiftData.ModelContext) {
        _viewModel = StateObject(wrappedValue: AppViewModel(
            musicService: musicService,
            modelContext: modelContext
        ))
    }

    var body: some View {
        Group {
            if viewModel.isAuthorized {
                PlayerView(player: viewModel.player) {
                    viewModel.openManage()
                }
            } else {
                authorizationView
            }
        }
        .task {
            await viewModel.onAppear()
        }
        .sheet(isPresented: $viewModel.showingManage) {
            ManageView(
                player: viewModel.player,
                onAddTapped: { viewModel.openPicker() },
                onDismiss: { viewModel.closeManage() }
            )
            .sheet(isPresented: $viewModel.showingPicker) {
                SongPickerView(
                    player: viewModel.player,
                    musicService: viewModel.musicService,
                    onDismiss: { viewModel.closePicker() }
                )
            }
        }
        .alert("Authorization Required", isPresented: .init(
            get: { viewModel.authorizationError != nil },
            set: { if !$0 { viewModel.authorizationError = nil } }
        )) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let error = viewModel.authorizationError {
                Text(error)
            }
        }
    }

    private var authorizationView: some View {
        VStack(spacing: 24) {
            Image(systemName: "music.note.list")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("Welcome to Shfl")
                    .font(.title2.bold())

                Text("Connect to Apple Music to start shuffling")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button("Connect Apple Music") {
                Task {
                    await viewModel.requestAuthorization()
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(32)
    }
}
```

**Step 3: Update ShflApp**

```swift
// Shfl/ShflApp.swift
import SwiftUI
import SwiftData

@main
struct ShflApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([PersistedSong.self])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            MainView(
                musicService: AppleMusicService(),
                modelContext: sharedModelContainer.mainContext
            )
        }
        .modelContainer(sharedModelContainer)
    }
}
```

**Step 4: Verify build**

Run: `xcodebuild -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 16' build`
Expected: BUILD SUCCEEDED

**Step 5: Commit**

```bash
git add .
git commit -m "feat: add MainView with authorization flow and navigation"
```

---

## Task 10: Polish and Error States

**Files:**
- Create: `Shfl/Views/Components/ErrorBanner.swift`
- Modify: `Shfl/Views/PlayerView.swift` (add error handling)

**Step 1: Create ErrorBanner component**

```swift
// Shfl/Views/Components/ErrorBanner.swift
import SwiftUI

struct ErrorBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.white)

            Text(message)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.red)
    }
}
```

**Step 2: Update PlayerView with error handling**

Add to PlayerView's body, after the capacity indicator:

```swift
// In PlayerView.swift, add after capacity indicator section:
// Error banner
if case .error(let error) = player.playbackState {
    ErrorBanner(message: error.localizedDescription) {
        // Dismiss error by attempting to play again
        Task { try? await player.play() }
    }
    .transition(.move(edge: .top).combined(with: .opacity))
}
```

**Step 3: Add loading indicator to PlayerView**

Update NowPlayingInfo section in PlayerView:

```swift
// Update the now playing section in controlsSection to show loading state
if case .loading(let song) = player.playbackState {
    VStack(spacing: 8) {
        ProgressView()
        NowPlayingInfo(title: song.title, artist: song.artist)
    }
    .transition(.opacity)
}
```

**Step 4: Verify build**

Run: `xcodebuild -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 16' build`
Expected: BUILD SUCCEEDED

**Step 5: Run all tests**

Run: `xcodebuild test -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: All tests PASS

**Step 6: Commit**

```bash
git add .
git commit -m "feat: add error handling and loading states to PlayerView"
```

---

## Task 11: Final Integration Testing

**Files:**
- Create: `ShflTests/Integration/AppFlowTests.swift`

**Step 1: Write integration tests**

```swift
// ShflTests/Integration/AppFlowTests.swift
import XCTest
@testable import Shfl

final class AppFlowTests: XCTestCase {
    func testFullPlaybackFlow() async throws {
        // Setup
        let mockService = MockMusicService()
        let player = await ShufflePlayer(musicService: mockService)

        // Add songs
        let songs = (1...5).map { i in
            Song(id: "\(i)", title: "Song \(i)", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        }

        for song in songs {
            try await player.addSong(song)
        }

        XCTAssertEqual(await player.songCount, 5)

        // Play
        try await player.play()
        try await Task.sleep(nanoseconds: 100_000_000)

        var state = await player.playbackState
        XCTAssertTrue(state.isPlaying)

        // Skip
        try await player.skipToNext()
        try await Task.sleep(nanoseconds: 100_000_000)

        state = await player.playbackState
        XCTAssertTrue(state.isPlaying)

        // Pause
        await player.pause()
        try await Task.sleep(nanoseconds: 100_000_000)

        state = await player.playbackState
        if case .paused = state {
            // Expected
        } else {
            XCTFail("Expected paused state")
        }

        // Resume
        try await player.togglePlayback()
        try await Task.sleep(nanoseconds: 100_000_000)

        state = await player.playbackState
        XCTAssertTrue(state.isPlaying)
    }

    func testCapacityEnforcement() async throws {
        let mockService = MockMusicService()
        let player = await ShufflePlayer(musicService: mockService)

        // Fill to capacity
        for i in 0..<120 {
            let song = Song(id: "\(i)", title: "Song \(i)", artist: "Artist", albumTitle: "Album", artworkURL: nil)
            try await player.addSong(song)
        }

        XCTAssertEqual(await player.songCount, 120)
        XCTAssertEqual(await player.remainingCapacity, 0)

        // Try to exceed
        let extraSong = Song(id: "extra", title: "Extra", artist: "Artist", albumTitle: "Album", artworkURL: nil)

        do {
            try await player.addSong(extraSong)
            XCTFail("Should throw capacity error")
        } catch ShufflePlayerError.capacityReached {
            // Expected
        }
    }
}
```

**Step 2: Run all tests**

Run: `xcodebuild test -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: All tests PASS

**Step 3: Final commit**

```bash
git add .
git commit -m "test: add integration tests for app flow and capacity"
```

---

## Summary

**Total Tasks:** 11
**Estimated commits:** 11

**Architecture:**
- Domain layer: Song, PlaybackState, ShufflePlayer, MusicService protocol
- Data layer: PersistedSong, SongRepository (SwiftData)
- Services: AppleMusicService (MusicKit implementation)
- Views: PlayerView, ManageView, SongPickerView + components

**Key Design Decisions:**
1. `ShufflePlayer` is platform-agnostic - all MusicKit details hidden behind protocol
2. State machine for playback avoids boolean complexity
3. 120 song limit enforced in domain layer
4. AsyncStream for reactive playback state updates
5. SwiftData for simple persistence of song IDs
6. TDD approach for all domain logic

**Testing Strategy:**
- MockMusicService enables full unit testing without Apple dependencies
- Integration tests verify complete flows
- MusicKit integration tested on device only

Now let me save this plan and update my progress:

<function_calls>
<invoke name="TodoWrite">
<parameter name="todos">[{"content": "Research MusicKit patterns and SwiftUI best practices for iOS music apps", "status": "completed", "activeForm": "Researching MusicKit and SwiftUI patterns"}, {"content": "Write complete implementation plan document", "status": "completed", "activeForm": "Writing implementation plan document"}, {"content": "Save plan to docs/plans/ and offer execution choice", "status": "completed", "activeForm": "Saving plan and offering execution options"}]