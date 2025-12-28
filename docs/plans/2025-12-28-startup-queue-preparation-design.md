# Startup Queue Preparation (Progressive Loading)

## Problem

When the app first loads and nothing is playing, there's a multi-second delay when hitting the play button. This happens because `setQueue(songs:)` fetches full `MusicKit.Song` objects from the library for all songs in the shuffle queue - a slow operation.

## Solution

Progressive queue loading: prepare just the first 2 songs immediately (enough to start playback), then append the remaining songs in the background.

## Design

### Strategy

**Current flow:**
```
prepareQueue() → fetch ALL songs → set queue → ready
```

**New flow:**
```
prepareQueue() → fetch first 2 songs → set queue → ready for play
             ↘ background: fetch remaining → insert at .tail
```

We only need 2 songs to start playback (current + next), then we backfill.

### MusicService Protocol Changes

Add two new methods:

```swift
func setInitialQueue(songs: [Song]) async throws
func appendToQueue(songs: [Song]) async throws
```

### AppleMusicService Implementation

```swift
func setInitialQueue(songs: [Song]) async throws {
    let ids = songs.prefix(2).map { MusicItemID($0.id) }
    var request = MusicLibraryRequest<MusicKit.Song>()
    request.filter(matching: \.id, memberOf: ids)
    let response = try await request.response()

    let queue = ApplicationMusicPlayer.Queue(for: response.items, startingAt: nil)
    player.queue = queue
    player.state.shuffleMode = .songs
}

func appendToQueue(songs: [Song]) async throws {
    for song in songs {
        let id = MusicItemID(song.id)
        var request = MusicLibraryRequest<MusicKit.Song>()
        request.filter(matching: \.id, memberOf: [id])
        let response = try await request.response()

        guard let musicKitSong = response.items.first else { continue }
        try await player.queue.insert(musicKitSong, position: .tail)
    }
}
```

Note: append fetches one at a time to handle MusicKit's transient state issue.

### ShufflePlayer Changes

State tracking:

```swift
private var initialQueueSongIds: Set<String> = []

var isReadyToPlay: Bool {
    let currentIds = Set(songs.map(\.id))
    return !initialQueueSongIds.isEmpty &&
           initialQueueSongIds.isSubset(of: currentIds)
}
```

Queue preparation:

```swift
func prepareQueue() async throws {
    guard !songs.isEmpty else { return }

    // 1. Set initial queue with first 2 songs
    let initialSongs = Array(songs.prefix(2))
    try await musicService.setInitialQueue(songs: initialSongs)
    initialQueueSongIds = Set(initialSongs.map(\.id))

    // 2. Background: append remaining songs
    let remainingSongs = Array(songs.dropFirst(2))
    if !remainingSongs.isEmpty {
        Task {
            try? await musicService.appendToQueue(songs: remainingSongs)
        }
    }
}
```

Modified play():

```swift
func play() async throws {
    guard !songs.isEmpty else { return }
    playedSongIds.removeAll()
    lastObservedSongId = nil

    if !isReadyToPlay {
        try await prepareQueue()
    }
    try await musicService.play()
}
```

### AppViewModel Changes

In `onAppear()`, after loading songs (unchanged from v1):

```swift
Task { try? await player.prepareQueue() }
```

## Files Changed

1. `Shfl/Domain/Protocols/MusicService.swift` - add protocol methods
2. `Shfl/Services/AppleMusicService.swift` - implement setInitialQueue, appendToQueue
3. `Shfl/Services/MockMusicService.swift` - stub implementations
4. `Shfl/Domain/ShufflePlayer.swift` - replace preparedSongIds with initialQueueSongIds, update prepareQueue()

## Behavior

- App launches → songs load → first 2 songs prepared → **ready in ~200ms**
- Remaining songs append in background
- User hits play → instant playback
- Songs change → initialQueueSongIds clears → next play re-prepares
