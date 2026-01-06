# Shuffle Algorithm Settings Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add settings to choose between 5 shuffle algorithms (Pure Random, Full Shuffle, Least Recent, Least Played, Artist Spacing).

**Architecture:** New `ShuffleAlgorithm` enum stored in UserDefaults, `QueueShuffler` transforms song list before queue setup, settings UI matches autofill pattern.

**Tech Stack:** SwiftUI, MusicKit (for playCount/lastPlayedDate), UserDefaults via @AppStorage.

---

## Task 1: Add playCount and lastPlayedDate to Song Model

**Files:**
- Modify: `Shfl/Domain/Models/Song.swift`
- Modify: `ShflTests/Domain/SongTests.swift`

**Step 1: Write failing tests for new Song fields**

In `ShflTests/Domain/SongTests.swift`, add:

```swift
func testSongWithPlayCount() {
    let song = Song(
        id: "1",
        title: "Test",
        artist: "Artist",
        albumTitle: "Album",
        artworkURL: nil,
        playCount: 42,
        lastPlayedDate: nil
    )
    XCTAssertEqual(song.playCount, 42)
}

func testSongWithLastPlayedDate() {
    let date = Date(timeIntervalSince1970: 1000000)
    let song = Song(
        id: "1",
        title: "Test",
        artist: "Artist",
        albumTitle: "Album",
        artworkURL: nil,
        playCount: 0,
        lastPlayedDate: date
    )
    XCTAssertEqual(song.lastPlayedDate, date)
}

func testSongDefaultValues() {
    let song = Song(
        id: "1",
        title: "Test",
        artist: "Artist",
        albumTitle: "Album",
        artworkURL: nil
    )
    XCTAssertEqual(song.playCount, 0)
    XCTAssertNil(song.lastPlayedDate)
}
```

**Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project Shfl.xcodeproj -scheme Shfl -destination 'id=62959AFB-80E8-4CCF-B0C0-24FCE8302E67' -only-testing:ShflTests/SongTests 2>&1 | grep -E "(passed|failed|error:)"`

Expected: Compilation error - extra arguments in call

**Step 3: Update Song model with new fields**

Replace `Shfl/Domain/Models/Song.swift`:

```swift
import Foundation

struct Song: Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let artist: String
    let albumTitle: String
    let artworkURL: URL?
    let playCount: Int
    let lastPlayedDate: Date?

    init(
        id: String,
        title: String,
        artist: String,
        albumTitle: String,
        artworkURL: URL?,
        playCount: Int = 0,
        lastPlayedDate: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.albumTitle = albumTitle
        self.artworkURL = artworkURL
        self.playCount = playCount
        self.lastPlayedDate = lastPlayedDate
    }
}
```

**Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project Shfl.xcodeproj -scheme Shfl -destination 'id=62959AFB-80E8-4CCF-B0C0-24FCE8302E67' -only-testing:ShflTests/SongTests 2>&1 | grep -E "(passed|failed|error:)"`

Expected: All SongTests pass

**Step 5: Commit**

```bash
git add Shfl/Domain/Models/Song.swift ShflTests/Domain/SongTests.swift
git commit -m "feat(song): add playCount and lastPlayedDate fields"
```

---

## Task 2: Update AppleMusicService to Map New Fields

**Files:**
- Modify: `Shfl/Services/AppleMusicService.swift:63-71` (fetchLibrarySongs)
- Modify: `Shfl/Services/AppleMusicService.swift:85-93` (searchLibrarySongs)
- Modify: `Shfl/Services/AppleMusicService.swift:198-204` (mapPlaybackState)

**Step 1: Update fetchLibrarySongs to include playCount and lastPlayedDate**

In `Shfl/Services/AppleMusicService.swift`, update the map at line 63-71:

```swift
let songs = response.items.map { musicKitSong in
    Song(
        id: musicKitSong.id.rawValue,
        title: musicKitSong.title,
        artist: musicKitSong.artistName,
        albumTitle: musicKitSong.albumTitle ?? "",
        artworkURL: nil,
        playCount: musicKitSong.playCount ?? 0,
        lastPlayedDate: musicKitSong.lastPlayedDate
    )
}
```

**Step 2: Update searchLibrarySongs similarly**

At line 85-93:

```swift
return response.songs.map { musicKitSong in
    Song(
        id: musicKitSong.id.rawValue,
        title: musicKitSong.title,
        artist: musicKitSong.artistName,
        albumTitle: musicKitSong.albumTitle ?? "",
        artworkURL: nil,
        playCount: musicKitSong.playCount ?? 0,
        lastPlayedDate: musicKitSong.lastPlayedDate
    )
}
```

**Step 3: Update mapPlaybackState similarly**

At line 198-204:

```swift
let song = Song(
    id: musicKitSong.id.rawValue,
    title: musicKitSong.title,
    artist: musicKitSong.artistName,
    albumTitle: musicKitSong.albumTitle ?? "",
    artworkURL: musicKitSong.artwork?.url(width: 300, height: 300),
    playCount: musicKitSong.playCount ?? 0,
    lastPlayedDate: musicKitSong.lastPlayedDate
)
```

**Step 4: Build to verify compilation**

Run: `xcodebuild build -project Shfl.xcodeproj -scheme Shfl -destination 'generic/platform=iOS Simulator' 2>&1 | grep -E "(BUILD|error:)"`

Expected: BUILD SUCCEEDED

**Step 5: Commit**

```bash
git add Shfl/Services/AppleMusicService.swift
git commit -m "feat(music): map playCount and lastPlayedDate from MusicKit"
```

---

## Task 3: Create ShuffleAlgorithm Enum

**Files:**
- Create: `Shfl/Domain/Models/ShuffleAlgorithm.swift`
- Create: `ShflTests/Domain/ShuffleAlgorithmTests.swift`

**Step 1: Write tests for ShuffleAlgorithm**

Create `ShflTests/Domain/ShuffleAlgorithmTests.swift`:

```swift
import XCTest
@testable import Shfl

final class ShuffleAlgorithmTests: XCTestCase {
    func testAllCasesCount() {
        XCTAssertEqual(ShuffleAlgorithm.allCases.count, 5)
    }

    func testDisplayNames() {
        XCTAssertEqual(ShuffleAlgorithm.pureRandom.displayName, "Pure Random")
        XCTAssertEqual(ShuffleAlgorithm.noRepeat.displayName, "Full Shuffle")
        XCTAssertEqual(ShuffleAlgorithm.weightedByRecency.displayName, "Least Recent")
        XCTAssertEqual(ShuffleAlgorithm.weightedByPlayCount.displayName, "Least Played")
        XCTAssertEqual(ShuffleAlgorithm.artistSpacing.displayName, "Artist Spacing")
    }

    func testRawValues() {
        XCTAssertEqual(ShuffleAlgorithm.pureRandom.rawValue, "pureRandom")
        XCTAssertEqual(ShuffleAlgorithm.noRepeat.rawValue, "noRepeat")
        XCTAssertEqual(ShuffleAlgorithm.weightedByRecency.rawValue, "weightedByRecency")
        XCTAssertEqual(ShuffleAlgorithm.weightedByPlayCount.rawValue, "weightedByPlayCount")
        XCTAssertEqual(ShuffleAlgorithm.artistSpacing.rawValue, "artistSpacing")
    }

    func testDescriptions() {
        XCTAssertTrue(ShuffleAlgorithm.pureRandom.description.contains("randomly"))
        XCTAssertTrue(ShuffleAlgorithm.noRepeat.description.contains("every song"))
        XCTAssertTrue(ShuffleAlgorithm.weightedByRecency.description.contains("recently"))
        XCTAssertTrue(ShuffleAlgorithm.weightedByPlayCount.description.contains("fewer plays"))
        XCTAssertTrue(ShuffleAlgorithm.artistSpacing.description.contains("artist"))
    }
}
```

**Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project Shfl.xcodeproj -scheme Shfl -destination 'id=62959AFB-80E8-4CCF-B0C0-24FCE8302E67' -only-testing:ShflTests/ShuffleAlgorithmTests 2>&1 | grep -E "(passed|failed|error:)"`

Expected: Compilation error - cannot find ShuffleAlgorithm

**Step 3: Create ShuffleAlgorithm enum**

Create `Shfl/Domain/Models/ShuffleAlgorithm.swift`:

```swift
import Foundation

enum ShuffleAlgorithm: String, CaseIterable, Sendable, Hashable {
    case pureRandom = "pureRandom"
    case noRepeat = "noRepeat"
    case weightedByRecency = "weightedByRecency"
    case weightedByPlayCount = "weightedByPlayCount"
    case artistSpacing = "artistSpacing"

    var displayName: String {
        switch self {
        case .pureRandom: return "Pure Random"
        case .noRepeat: return "Full Shuffle"
        case .weightedByRecency: return "Least Recent"
        case .weightedByPlayCount: return "Least Played"
        case .artistSpacing: return "Artist Spacing"
        }
    }

    var description: String {
        switch self {
        case .pureRandom:
            return "Picks songs randomly. The same song may play again before others."
        case .noRepeat:
            return "Shuffles your queue and plays every song before repeating."
        case .weightedByRecency:
            return "Prioritizes songs you haven't listened to recently."
        case .weightedByPlayCount:
            return "Prioritizes songs with fewer plays."
        case .artistSpacing:
            return "Shuffles while avoiding back-to-back songs from the same artist."
        }
    }
}
```

**Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project Shfl.xcodeproj -scheme Shfl -destination 'id=62959AFB-80E8-4CCF-B0C0-24FCE8302E67' -only-testing:ShflTests/ShuffleAlgorithmTests 2>&1 | grep -E "(passed|failed|error:)"`

Expected: All ShuffleAlgorithmTests pass

**Step 5: Commit**

```bash
git add Shfl/Domain/Models/ShuffleAlgorithm.swift ShflTests/Domain/ShuffleAlgorithmTests.swift
git commit -m "feat(shuffle): add ShuffleAlgorithm enum with 5 algorithms"
```

---

## Task 4: Create QueueShuffler

**Files:**
- Create: `Shfl/Domain/QueueShuffler.swift`
- Create: `ShflTests/Domain/QueueShufflerTests.swift`

**Step 1: Write tests for QueueShuffler**

Create `ShflTests/Domain/QueueShufflerTests.swift`:

```swift
import XCTest
@testable import Shfl

final class QueueShufflerTests: XCTestCase {

    private func makeSong(
        id: String,
        artist: String = "Artist",
        playCount: Int = 0,
        lastPlayedDate: Date? = nil
    ) -> Song {
        Song(
            id: id,
            title: "Song \(id)",
            artist: artist,
            albumTitle: "Album",
            artworkURL: nil,
            playCount: playCount,
            lastPlayedDate: lastPlayedDate
        )
    }

    // MARK: - Pure Random

    func testPureRandomCanProduceDuplicates() {
        let songs = (1...3).map { makeSong(id: "\($0)") }
        let shuffler = QueueShuffler(algorithm: .pureRandom)

        // With only 3 songs and 100 element output, duplicates are guaranteed
        let result = shuffler.shuffle(songs, count: 100)

        XCTAssertEqual(result.count, 100)
        let uniqueIds = Set(result.map(\.id))
        XCTAssertLessThanOrEqual(uniqueIds.count, 3)
    }

    // MARK: - No Repeat

    func testNoRepeatContainsAllSongsOnce() {
        let songs = (1...10).map { makeSong(id: "\($0)") }
        let shuffler = QueueShuffler(algorithm: .noRepeat)

        let result = shuffler.shuffle(songs)

        XCTAssertEqual(result.count, 10)
        XCTAssertEqual(Set(result.map(\.id)), Set(songs.map(\.id)))
    }

    func testNoRepeatShufflesOrder() {
        let songs = (1...20).map { makeSong(id: "\($0)") }
        let shuffler = QueueShuffler(algorithm: .noRepeat)

        // Run multiple times - at least one should differ from original
        let results = (0..<10).map { _ in shuffler.shuffle(songs).map(\.id) }
        let originalOrder = songs.map(\.id)

        let anyDifferent = results.contains { $0 != originalOrder }
        XCTAssertTrue(anyDifferent, "Shuffle should change order at least once in 10 tries")
    }

    // MARK: - Weighted by Recency

    func testWeightedByRecencyPrioritizesOlderSongs() {
        let now = Date()
        let songs = [
            makeSong(id: "recent", lastPlayedDate: now),
            makeSong(id: "old", lastPlayedDate: now.addingTimeInterval(-86400 * 30)),
            makeSong(id: "never", lastPlayedDate: nil)
        ]
        let shuffler = QueueShuffler(algorithm: .weightedByRecency)

        // Run multiple times and track first position frequency
        var firstPositionCounts: [String: Int] = [:]
        for _ in 0..<100 {
            let result = shuffler.shuffle(songs)
            let firstId = result[0].id
            firstPositionCounts[firstId, default: 0] += 1
        }

        // "never" and "old" should appear first more often than "recent"
        let neverCount = firstPositionCounts["never"] ?? 0
        let oldCount = firstPositionCounts["old"] ?? 0
        let recentCount = firstPositionCounts["recent"] ?? 0

        XCTAssertGreaterThan(neverCount + oldCount, recentCount)
    }

    // MARK: - Weighted by Play Count

    func testWeightedByPlayCountPrioritizesLessPlayed() {
        let songs = [
            makeSong(id: "played100", playCount: 100),
            makeSong(id: "played10", playCount: 10),
            makeSong(id: "played0", playCount: 0)
        ]
        let shuffler = QueueShuffler(algorithm: .weightedByPlayCount)

        // Run multiple times and track first position frequency
        var firstPositionCounts: [String: Int] = [:]
        for _ in 0..<100 {
            let result = shuffler.shuffle(songs)
            let firstId = result[0].id
            firstPositionCounts[firstId, default: 0] += 1
        }

        // Less played songs should appear first more often
        let played0Count = firstPositionCounts["played0"] ?? 0
        let played10Count = firstPositionCounts["played10"] ?? 0
        let played100Count = firstPositionCounts["played100"] ?? 0

        XCTAssertGreaterThan(played0Count + played10Count, played100Count)
    }

    // MARK: - Artist Spacing

    func testArtistSpacingAvoidsAdjacentSameArtist() {
        let songs = [
            makeSong(id: "a1", artist: "Artist A"),
            makeSong(id: "a2", artist: "Artist A"),
            makeSong(id: "b1", artist: "Artist B"),
            makeSong(id: "b2", artist: "Artist B"),
            makeSong(id: "c1", artist: "Artist C"),
            makeSong(id: "c2", artist: "Artist C")
        ]
        let shuffler = QueueShuffler(algorithm: .artistSpacing)

        // Run multiple times - should never have adjacent same artists (when avoidable)
        for _ in 0..<20 {
            let result = shuffler.shuffle(songs)

            for i in 0..<(result.count - 1) {
                let current = result[i].artist
                let next = result[i + 1].artist
                XCTAssertNotEqual(current, next, "Adjacent songs should have different artists")
            }
        }
    }

    func testArtistSpacingHandlesSingleArtist() {
        // When all songs are same artist, can't avoid adjacent
        let songs = (1...5).map { makeSong(id: "\($0)", artist: "Same Artist") }
        let shuffler = QueueShuffler(algorithm: .artistSpacing)

        let result = shuffler.shuffle(songs)

        // Should still return all songs
        XCTAssertEqual(result.count, 5)
        XCTAssertEqual(Set(result.map(\.id)), Set(songs.map(\.id)))
    }

    // MARK: - Edge Cases

    func testEmptyInput() {
        let shuffler = QueueShuffler(algorithm: .noRepeat)
        let result = shuffler.shuffle([])
        XCTAssertTrue(result.isEmpty)
    }

    func testSingleSong() {
        let songs = [makeSong(id: "only")]
        let shuffler = QueueShuffler(algorithm: .noRepeat)

        let result = shuffler.shuffle(songs)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].id, "only")
    }
}
```

**Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project Shfl.xcodeproj -scheme Shfl -destination 'id=62959AFB-80E8-4CCF-B0C0-24FCE8302E67' -only-testing:ShflTests/QueueShufflerTests 2>&1 | grep -E "(passed|failed|error:)"`

Expected: Compilation error - cannot find QueueShuffler

**Step 3: Create QueueShuffler**

Create `Shfl/Domain/QueueShuffler.swift`:

```swift
import Foundation

struct QueueShuffler: Sendable {
    let algorithm: ShuffleAlgorithm

    func shuffle(_ songs: [Song], count: Int? = nil) -> [Song] {
        guard !songs.isEmpty else { return [] }

        switch algorithm {
        case .pureRandom:
            return pureRandom(songs, count: count ?? songs.count)
        case .noRepeat:
            return songs.shuffled()
        case .weightedByRecency:
            return weightedByRecency(songs)
        case .weightedByPlayCount:
            return weightedByPlayCount(songs)
        case .artistSpacing:
            return artistSpacing(songs)
        }
    }

    // MARK: - Pure Random

    private func pureRandom(_ songs: [Song], count: Int) -> [Song] {
        (0..<count).map { _ in songs.randomElement()! }
    }

    // MARK: - Weighted by Recency

    private func weightedByRecency(_ songs: [Song]) -> [Song] {
        // Sort by lastPlayedDate ascending (nil = never played = first)
        // Then shuffle within tiers to add variety
        let sorted = songs.sorted { song1, song2 in
            let date1 = song1.lastPlayedDate ?? .distantPast
            let date2 = song2.lastPlayedDate ?? .distantPast
            return date1 < date2
        }
        return shuffleWithinTiers(sorted, tierSize: max(1, songs.count / 10))
    }

    // MARK: - Weighted by Play Count

    private func weightedByPlayCount(_ songs: [Song]) -> [Song] {
        // Sort by playCount ascending (0 plays = first)
        // Then shuffle within tiers
        let sorted = songs.sorted { $0.playCount < $1.playCount }
        return shuffleWithinTiers(sorted, tierSize: max(1, songs.count / 10))
    }

    private func shuffleWithinTiers(_ songs: [Song], tierSize: Int) -> [Song] {
        var result: [Song] = []
        var remaining = songs

        while !remaining.isEmpty {
            let tierEnd = min(tierSize, remaining.count)
            let tier = Array(remaining.prefix(tierEnd))
            remaining = Array(remaining.dropFirst(tierEnd))
            result.append(contentsOf: tier.shuffled())
        }

        return result
    }

    // MARK: - Artist Spacing

    private func artistSpacing(_ songs: [Song]) -> [Song] {
        guard songs.count > 1 else { return songs }

        // Group songs by artist
        var byArtist: [String: [Song]] = [:]
        for song in songs.shuffled() {
            byArtist[song.artist, default: []].append(song)
        }

        var result: [Song] = []
        var recentArtists: [String] = []
        let spacingWindow = min(3, byArtist.keys.count - 1)

        while result.count < songs.count {
            // Find artist not in recent window with songs remaining
            let availableArtist = byArtist.keys.first { artist in
                !recentArtists.suffix(spacingWindow).contains(artist) &&
                !(byArtist[artist]?.isEmpty ?? true)
            }

            // Fall back to any artist with songs if spacing impossible
            let chosenArtist = availableArtist ?? byArtist.keys.first { !(byArtist[$0]?.isEmpty ?? true) }

            guard let artist = chosenArtist,
                  var artistSongs = byArtist[artist],
                  !artistSongs.isEmpty else {
                break
            }

            let song = artistSongs.removeFirst()
            byArtist[artist] = artistSongs
            result.append(song)
            recentArtists.append(artist)
        }

        return result
    }
}
```

**Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project Shfl.xcodeproj -scheme Shfl -destination 'id=62959AFB-80E8-4CCF-B0C0-24FCE8302E67' -only-testing:ShflTests/QueueShufflerTests 2>&1 | grep -E "(passed|failed|error:)"`

Expected: All QueueShufflerTests pass

**Step 5: Commit**

```bash
git add Shfl/Domain/QueueShuffler.swift ShflTests/Domain/QueueShufflerTests.swift
git commit -m "feat(shuffle): add QueueShuffler with 5 algorithm implementations"
```

---

## Task 5: Create ShuffleAlgorithmSettingsView

**Files:**
- Create: `Shfl/Views/Settings/ShuffleAlgorithmSettingsView.swift`
- Create: `ShflTests/Views/ShuffleAlgorithmSettingsViewTests.swift`

**Step 1: Write tests for settings view**

Create `ShflTests/Views/ShuffleAlgorithmSettingsViewTests.swift`:

```swift
import XCTest
import SwiftUI
@testable import Shfl

final class ShuffleAlgorithmSettingsViewTests: XCTestCase {

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "shuffleAlgorithm")
        super.tearDown()
    }

    func testDefaultAlgorithmIsNoRepeat() {
        UserDefaults.standard.removeObject(forKey: "shuffleAlgorithm")
        let raw = UserDefaults.standard.string(forKey: "shuffleAlgorithm")
        let algorithm = raw.flatMap { ShuffleAlgorithm(rawValue: $0) } ?? .noRepeat
        XCTAssertEqual(algorithm, .noRepeat)
    }

    func testAlgorithmPersistsToUserDefaults() {
        UserDefaults.standard.set(ShuffleAlgorithm.artistSpacing.rawValue, forKey: "shuffleAlgorithm")
        let raw = UserDefaults.standard.string(forKey: "shuffleAlgorithm")!
        let algorithm = ShuffleAlgorithm(rawValue: raw)
        XCTAssertEqual(algorithm, .artistSpacing)
    }

    func testAllAlgorithmsHaveDescriptions() {
        for algorithm in ShuffleAlgorithm.allCases {
            XCTAssertFalse(algorithm.description.isEmpty, "\(algorithm) should have description")
        }
    }

    func testAllAlgorithmsHaveDisplayNames() {
        for algorithm in ShuffleAlgorithm.allCases {
            XCTAssertFalse(algorithm.displayName.isEmpty, "\(algorithm) should have display name")
        }
    }
}
```

**Step 2: Run tests to verify they pass (these are UserDefaults tests)**

Run: `xcodebuild test -project Shfl.xcodeproj -scheme Shfl -destination 'id=62959AFB-80E8-4CCF-B0C0-24FCE8302E67' -only-testing:ShflTests/ShuffleAlgorithmSettingsViewTests 2>&1 | grep -E "(passed|failed|error:)"`

Expected: All pass (tests don't require the view yet)

**Step 3: Create ShuffleAlgorithmSettingsView**

Create `Shfl/Views/Settings/ShuffleAlgorithmSettingsView.swift`:

```swift
import SwiftUI

struct ShuffleAlgorithmSettingsView: View {
    @AppStorage("shuffleAlgorithm") private var algorithmRaw: String = ShuffleAlgorithm.noRepeat.rawValue

    private var algorithm: ShuffleAlgorithm {
        ShuffleAlgorithm(rawValue: algorithmRaw) ?? .noRepeat
    }

    var body: some View {
        Form {
            Section {
                ForEach(ShuffleAlgorithm.allCases, id: \.self) { algo in
                    Button {
                        algorithmRaw = algo.rawValue
                    } label: {
                        HStack {
                            Text(algo.displayName)
                                .foregroundStyle(.primary)
                            Spacer()
                            if algorithm == algo {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }
            } footer: {
                Text(algorithm.description)
            }
        }
        .navigationTitle("Shuffle Algorithm")
    }
}

#Preview {
    NavigationStack {
        ShuffleAlgorithmSettingsView()
    }
}
```

**Step 4: Build to verify compilation**

Run: `xcodebuild build -project Shfl.xcodeproj -scheme Shfl -destination 'generic/platform=iOS Simulator' 2>&1 | grep -E "(BUILD|error:)"`

Expected: BUILD SUCCEEDED

**Step 5: Commit**

```bash
git add Shfl/Views/Settings/ShuffleAlgorithmSettingsView.swift ShflTests/Views/ShuffleAlgorithmSettingsViewTests.swift
git commit -m "feat(settings): add ShuffleAlgorithmSettingsView"
```

---

## Task 6: Update SettingsView to Link to New View

**Files:**
- Modify: `Shfl/Views/SettingsView.swift:19-24`

**Step 1: Update SettingsView navigation link**

Replace lines 19-24 in `Shfl/Views/SettingsView.swift`:

```swift
NavigationLink {
    ShuffleAlgorithmSettingsView()
} label: {
    Label("Shuffle Algorithm", systemImage: "shuffle")
}
```

**Step 2: Build to verify**

Run: `xcodebuild build -project Shfl.xcodeproj -scheme Shfl -destination 'generic/platform=iOS Simulator' 2>&1 | grep -E "(BUILD|error:)"`

Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add Shfl/Views/SettingsView.swift
git commit -m "feat(settings): link to shuffle algorithm settings"
```

---

## Task 7: Integrate QueueShuffler into ShufflePlayer

**Files:**
- Modify: `Shfl/Domain/ShufflePlayer.swift`
- Modify: `ShflTests/Domain/ShufflePlayerTests.swift`

**Step 1: Write integration test**

Add to `ShflTests/Domain/ShufflePlayerTests.swift`:

```swift
func testPlayAppliesShuffleAlgorithm() async throws {
    // Set algorithm to noRepeat (default)
    UserDefaults.standard.set("noRepeat", forKey: "shuffleAlgorithm")

    let songs = (1...5).map { i in
        Song(id: "\(i)", title: "Song \(i)", artist: "Artist", albumTitle: "Album", artworkURL: nil)
    }

    for song in songs {
        try player.addSong(song)
    }

    try await player.play()

    // Verify queue was set (shuffler was applied)
    let queuedSongs = await mockService.lastQueuedSongs
    XCTAssertEqual(queuedSongs.count, 5)
    XCTAssertEqual(Set(queuedSongs.map(\.id)), Set(songs.map(\.id)))
}
```

**Step 2: Run test to verify it passes (current behavior already works)**

Run: `xcodebuild test -project Shfl.xcodeproj -scheme Shfl -destination 'id=62959AFB-80E8-4CCF-B0C0-24FCE8302E67' -only-testing:ShflTests/ShufflePlayerTests/testPlayAppliesShuffleAlgorithm 2>&1 | grep -E "(passed|failed|error:)"`

Expected: Pass

**Step 3: Update ShufflePlayer.play() to use QueueShuffler**

In `Shfl/Domain/ShufflePlayer.swift`, update the `play()` method (around line 124):

```swift
func play() async throws {
    guard !songs.isEmpty else { return }
    playedSongIds.removeAll()
    lastObservedSongId = nil

    let algorithmRaw = UserDefaults.standard.string(forKey: "shuffleAlgorithm") ?? ShuffleAlgorithm.noRepeat.rawValue
    let algorithm = ShuffleAlgorithm(rawValue: algorithmRaw) ?? .noRepeat
    let shuffler = QueueShuffler(algorithm: algorithm)
    let shuffledSongs = shuffler.shuffle(songs)

    try await musicService.setQueue(songs: shuffledSongs)
    preparedSongIds = Set(songs.map(\.id))
    try await musicService.play()
}
```

**Step 4: Also update prepareQueue() for consistency**

Update `prepareQueue()` (around line 116):

```swift
func prepareQueue() async throws {
    guard !songs.isEmpty else { return }

    let algorithmRaw = UserDefaults.standard.string(forKey: "shuffleAlgorithm") ?? ShuffleAlgorithm.noRepeat.rawValue
    let algorithm = ShuffleAlgorithm(rawValue: algorithmRaw) ?? .noRepeat
    let shuffler = QueueShuffler(algorithm: algorithm)
    let shuffledSongs = shuffler.shuffle(songs)

    try await musicService.setQueue(songs: shuffledSongs)
    preparedSongIds = Set(songs.map(\.id))
}
```

**Step 5: Run all ShufflePlayer tests**

Run: `xcodebuild test -project Shfl.xcodeproj -scheme Shfl -destination 'id=62959AFB-80E8-4CCF-B0C0-24FCE8302E67' -only-testing:ShflTests/ShufflePlayerTests 2>&1 | grep -E "(passed|failed|error:)"`

Expected: All ShufflePlayerTests pass

**Step 6: Commit**

```bash
git add Shfl/Domain/ShufflePlayer.swift ShflTests/Domain/ShufflePlayerTests.swift
git commit -m "feat(shuffle): integrate QueueShuffler into ShufflePlayer"
```

---

## Task 8: Update MockMusicService for Testing

**Files:**
- Modify: `ShflTests/Mocks/MockMusicService.swift`

**Step 1: Update MockMusicService to not shuffle internally**

The mock currently shuffles in `setQueue`. Update to preserve order for testing:

In `ShflTests/Mocks/MockMusicService.swift`, update `setQueue` (line 70-89):

```swift
func setQueue(songs: [Song]) async throws {
    setQueueCallCount += 1
    lastQueuedSongs = songs
    queuedSongs = songs  // Don't shuffle - let QueueShuffler handle it
    currentIndex = 0

    switch currentState {
    case .playing, .paused:
        break
    default:
        if queuedSongs.isEmpty {
            updateState(.empty)
        } else {
            updateState(.stopped)
        }
    }
}
```

**Step 2: Run all tests to verify nothing broke**

Run: `xcodebuild test -project Shfl.xcodeproj -scheme Shfl -destination 'id=62959AFB-80E8-4CCF-B0C0-24FCE8302E67' 2>&1 | grep -E "(Test Suite|passed|failed|\*\* TEST)"`

Expected: All tests pass

**Step 3: Commit**

```bash
git add ShflTests/Mocks/MockMusicService.swift
git commit -m "test(mock): preserve queue order for shuffle algorithm testing"
```

---

## Task 9: Run Full Test Suite and Final Verification

**Step 1: Run complete test suite**

Run: `xcodebuild test -project Shfl.xcodeproj -scheme Shfl -destination 'id=62959AFB-80E8-4CCF-B0C0-24FCE8302E67' 2>&1 | grep -E "(Test Suite|passed|failed|\*\* TEST)"`

Expected: All tests pass (except pre-existing flaky test)

**Step 2: Build for device to verify no issues**

Run: `xcodebuild build -project Shfl.xcodeproj -scheme Shfl -destination 'generic/platform=iOS Simulator' 2>&1 | grep -E "(BUILD|error:)"`

Expected: BUILD SUCCEEDED

**Step 3: Review git log**

Run: `git log --oneline -10`

Expected: See all feature commits in order

---

## Summary

| Task | Description | Files |
|------|-------------|-------|
| 1 | Add playCount/lastPlayedDate to Song | Song.swift, SongTests.swift |
| 2 | Map new fields in AppleMusicService | AppleMusicService.swift |
| 3 | Create ShuffleAlgorithm enum | ShuffleAlgorithm.swift, tests |
| 4 | Create QueueShuffler | QueueShuffler.swift, tests |
| 5 | Create settings view | ShuffleAlgorithmSettingsView.swift, tests |
| 6 | Link settings in SettingsView | SettingsView.swift |
| 7 | Integrate shuffler into ShufflePlayer | ShufflePlayer.swift, tests |
| 8 | Update MockMusicService | MockMusicService.swift |
| 9 | Final verification | Full test suite |
