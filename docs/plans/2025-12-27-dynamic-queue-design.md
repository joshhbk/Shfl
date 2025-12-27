# Dynamic Queue Updates - Design Document

Keep playback queue in sync with library changes during active playback.

## Overview

**Problem:** Adding songs during playback (especially via Autofill) doesn't affect the active queue. Users who start with 5 songs and autofill to 120 still only hear those original 5 until they manually restart playback.

**Solution:** When songs are added or removed during active playback:
1. Track which songs have already played this session
2. Rebuild the upcoming queue with the updated song list (minus played songs)
3. Continue playback seamlessly (or with minimal disruption)

## Key Behaviors

- **Adding songs:** New songs get shuffled into the upcoming queue
- **Removing songs:** Removed songs are pruned from upcoming queue
- **Currently playing song:** Left alone even if removed (finishes naturally)
- **History:** Cleared when playback stops or user explicitly restarts

## Data Model Changes

**ShufflePlayer additions:**

```swift
@MainActor
final class ShufflePlayer: ObservableObject {
    // Existing
    @Published private(set) var songs: [Song] = []
    @Published private(set) var playbackState: PlaybackState = .empty

    // New
    private var playedSongIds: Set<String> = []
    private var lastObservedSongId: String? = nil
}
```

- `playedSongIds` - Songs that have finished playing this session. Excluded from queue rebuilds.
- `lastObservedSongId` - Tracks previous song to detect transitions.

**When history is cleared:**
- When playback state becomes `.stopped` or `.empty`
- When `play()` is called fresh (user explicitly restarts shuffle)

**When history is NOT cleared:**
- Pause/resume
- Song transitions during active playback

## Detection & Trigger Logic

**Detecting song transitions:**

```swift
private func handlePlaybackStateChange(_ newState: PlaybackState) {
    let newSongId = newState.currentSongId

    // Song changed - add previous to history
    if let lastId = lastObservedSongId, lastId != newSongId {
        playedSongIds.insert(lastId)
    }
    lastObservedSongId = newSongId

    // Clear history on stop/empty
    if case .stopped = newState { playedSongIds.removeAll() }
    if case .empty = newState { playedSongIds.removeAll() }

    playbackState = newState
}
```

**Triggering queue rebuild:**

```swift
func addSong(_ song: Song) throws {
    // existing validation...
    songs.append(song)
    rebuildQueueIfPlaying()
}

func removeSong(id: String) {
    songs.removeAll { $0.id == id }
    rebuildQueueIfPlaying()
}
```

## Queue Rebuild Flow

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

**PlaybackState helpers:**

```swift
extension PlaybackState {
    var isActive: Bool {
        switch self {
        case .playing, .paused, .loading: return true
        case .empty, .stopped, .error: return false
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

## MusicService Considerations

No protocol changes needed. Existing `setQueue(songs:)` works for rebuilds.

**Potential issue:** Setting `player.queue` during active playback might cause a brief hiccup. Accepted for MVP - optimize later if users notice.

## Edge Cases

| Scenario | Behavior |
|----------|----------|
| Add song while paused | Queue rebuilds, resumes from same spot |
| Remove currently playing song | Song finishes naturally, won't replay |
| Remove all songs during playback | Queue empties, playback stops |
| Add songs when all have been played | Queue rebuilds with just new songs |
| Autofill adds 50 songs | Single rebuild with all new songs shuffled in |
| Rapid add/remove | Multiple rebuilds fire, last one wins |
| Network failure during rebuild | Error swallowed, queue stays as-is |

## Testing

**Unit tests for ShufflePlayer:**

| Test | Verifies |
|------|----------|
| `testAddSongDuringPlaybackRebuildsQueue` | Adding song calls `setQueue` with unplayed songs |
| `testRemoveSongDuringPlaybackRebuildsQueue` | Removing song excludes it from rebuild |
| `testPlayedSongsExcludedFromRebuild` | Songs in history don't appear in queue |
| `testSongTransitionUpdatesHistory` | Previous song added to history on transition |
| `testHistoryClearedOnStop` | History emptied on `.stopped` state |
| `testHistoryClearedOnPlay` | Fresh `play()` clears history |
| `testNoRebuildWhenStopped` | Adding songs while stopped skips rebuild |
| `testRemoveCurrentlyPlayingSong` | Playback continues, song removed from list |

**MockMusicService additions:**

```swift
var setQueueCallCount = 0
var lastQueuedSongs: [Song] = []
```

## Open Questions

None at this time.
