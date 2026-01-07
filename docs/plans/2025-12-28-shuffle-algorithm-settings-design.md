# Shuffle Algorithm Settings - Design Document

Add a settings screen to let users choose between shuffle algorithms.

## Overview

**Algorithms:**
- **Pure Random** - True random each pick, songs can repeat before all are played
- **Full Shuffle** - Shuffles entire list, plays through all before any repeats (default)
- **Least Recent** - Songs not played recently are more likely to be picked
- **Least Played** - Less-played songs get priority
- **Artist Spacing** - Avoids back-to-back songs from the same artist

**UI:** List selection with checkmarks in a dedicated settings view, matching autofill settings pattern.

## Data Model

```swift
enum ShuffleAlgorithm: String, CaseIterable {
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
}
```

Stored in UserDefaults via `@AppStorage("shuffleAlgorithm")`, defaulting to `.noRepeat`.

## Algorithm Behavior

| Algorithm | Queue Order |
|-----------|-------------|
| Pure Random | `songs.map { _ in songs.randomElement()! }` - true random with repeats |
| Full Shuffle | `songs.shuffled()` - Fisher-Yates, no repeats until all played |
| Least Recent | Sort by `lastPlayedDate` ascending (never played first), shuffle within tiers |
| Least Played | Sort by `playCount` ascending, shuffle within tiers |
| Artist Spacing | Shuffle, then reorder to maximize artist gaps |

## Song Model Changes

Add fields to support weighted algorithms (from MusicKit):

```swift
struct Song: Identifiable, Equatable {
    let id: String
    let title: String
    let artist: String
    let album: String
    let artworkURL: URL?
    let duration: TimeInterval
    let playCount: Int           // New
    let lastPlayedDate: Date?    // New
}
```

## Settings UI

`ShuffleAlgorithmSettingsView` follows the autofill settings pattern:

```swift
struct ShuffleAlgorithmSettingsView: View {
    @AppStorage("shuffleAlgorithm") private var algorithmRaw: String = ShuffleAlgorithm.noRepeat.rawValue

    private var algorithm: ShuffleAlgorithm {
        ShuffleAlgorithm(rawValue: algorithmRaw) ?? .noRepeat
    }

    var body: some View {
        Form {
            Section {
                ForEach(Array(ShuffleAlgorithm.allCases), id: \.self) { algo in
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
                Text(algorithmDescription)
            }
        }
        .navigationTitle("Shuffle Algorithm")
    }
}
```

**Footer descriptions:**

| Algorithm | Description |
|-----------|-------------|
| Pure Random | "Picks songs randomly. The same song may play again before others." |
| Full Shuffle | "Shuffles your queue and plays every song before repeating." |
| Least Recent | "Prioritizes songs you haven't listened to recently." |
| Least Played | "Prioritizes songs with fewer plays." |
| Artist Spacing | "Shuffles while avoiding back-to-back songs from the same artist." |

## Shuffle Logic

New `QueueShuffler` transforms the song list before sending to MusicKit:

```swift
struct QueueShuffler {
    let algorithm: ShuffleAlgorithm

    func shuffle(_ songs: [Song]) -> [Song] {
        switch algorithm {
        case .pureRandom:
            return (0..<songs.count).map { _ in songs.randomElement()! }

        case .noRepeat:
            return songs.shuffled()

        case .weightedByRecency:
            return songs
                .sorted { ($0.lastPlayedDate ?? .distantPast) < ($1.lastPlayedDate ?? .distantPast) }
                .chunked(by: 10)
                .flatMap { $0.shuffled() }

        case .weightedByPlayCount:
            return songs
                .sorted { $0.playCount < $1.playCount }
                .chunked(by: 10)
                .flatMap { $0.shuffled() }

        case .artistSpacing:
            return spacedByArtist(songs.shuffled())
        }
    }

    private func spacedByArtist(_ songs: [Song]) -> [Song] {
        // Greedy algorithm: pick next song whose artist
        // is furthest from recent plays
    }
}
```

## Integration

`ShufflePlayer.play()` reads the setting and applies the shuffler:

```swift
func play() async throws {
    let algorithmRaw = UserDefaults.standard.string(forKey: "shuffleAlgorithm") ?? "noRepeat"
    let algorithm = ShuffleAlgorithm(rawValue: algorithmRaw) ?? .noRepeat
    let shuffler = QueueShuffler(algorithm: algorithm)

    let shuffledSongs = shuffler.shuffle(songs)
    try await musicService.setQueue(songs: shuffledSongs)
    // ...
}
```

## Testing

**QueueShuffler tests:**
- `pureRandom` can produce duplicates
- `noRepeat` contains each song exactly once
- `weightedByRecency` - songs with older/nil `lastPlayedDate` appear earlier on average
- `weightedByPlayCount` - songs with lower `playCount` appear earlier on average
- `artistSpacing` - no two adjacent songs share the same artist (when possible)

**ShuffleAlgorithmSettingsView tests:**
- Renders all 5 options
- Selection updates `@AppStorage` value
- Footer text updates based on selection

**Integration test:**
- `ShufflePlayer.play()` applies selected algorithm before setting queue

## Files to Change

1. `Shfl/Domain/Models/Song.swift` - Add `playCount` and `lastPlayedDate`
2. `Shfl/Domain/Models/ShuffleAlgorithm.swift` - New enum
3. `Shfl/Domain/QueueShuffler.swift` - New shuffle logic
4. `Shfl/Views/Settings/ShuffleAlgorithmSettingsView.swift` - New settings UI
5. `Shfl/Views/SettingsView.swift` - Link to new settings view
6. `Shfl/Services/AppleMusicService.swift` - Map new fields from MusicKit
7. `Shfl/Domain/ShufflePlayer.swift` - Apply shuffler in `play()`
8. `ShflTests/Domain/QueueShufflerTests.swift` - New algorithm tests
9. `ShflTests/Views/ShuffleAlgorithmSettingsViewTests.swift` - New UI tests
10. `ShflTests/Mocks/MockMusicService.swift` - Update mock songs with new fields
