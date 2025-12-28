# Startup Queue Preparation

## Problem

When the app first loads and nothing is playing, there's a multi-second delay when hitting the play button. This happens because `setQueue(songs:)` fetches full `MusicKit.Song` objects from the library for all songs in the shuffle queue - a slow operation.

## Solution

Prepare the MusicKit queue on app launch, in the background, after songs are loaded from persistence. When the user hits play, the queue is already set and playback is instant.

## Design

### State Tracking

Track which songs have been prepared using a Set of IDs:

```swift
private var preparedSongIds: Set<String> = []

var isQueuePrepared: Bool {
    Set(songs.map(\.id)) == preparedSongIds
}
```

This self-invalidates when songs are added or removed - no manual reset needed.

### ShufflePlayer Changes

New method:

```swift
func prepareQueue() async throws {
    guard !songs.isEmpty else { return }
    try await musicService.setQueue(songs: songs)
    preparedSongIds = Set(songs.map(\.id))
}
```

Modified `play()`:

```swift
func play() async throws {
    guard !songs.isEmpty else { return }
    playedSongIds.removeAll()
    lastObservedSongId = nil

    if !isQueuePrepared {
        try await musicService.setQueue(songs: songs)
        preparedSongIds = Set(songs.map(\.id))
    }
    try await musicService.play()
}
```

### AppViewModel Changes

In `onAppear()`, after loading songs:

```swift
func onAppear() async {
    isAuthorized = await musicService.isAuthorized

    do {
        let songs = try repository.loadSongs()
        for song in songs {
            try? player.addSong(song)
        }
    } catch {
        print("Failed to load songs: \(error)")
    }

    // Prepare queue in background
    Task { try? await player.prepareQueue() }
}
```

## Files Changed

1. `Shfl/Domain/ShufflePlayer.swift` - add state, prepareQueue(), modify play()
2. `Shfl/ViewModels/AppViewModel.swift` - call prepareQueue() after loading songs

## Behavior

- App launches → songs load from persistence → queue prepares in background
- User hits play → instant playback (queue already set)
- User adds/removes songs → `isQueuePrepared` automatically becomes false
- Next play → rebuilds queue (one-time cost per change)
