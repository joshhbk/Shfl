# Playback Fix & Click Wheel UI - Design Document

## Overview

Fix broken music playback and implement click wheel-style player controls with an optional progress bar.

## Problem

Music playback is completely broken since Apple Music integration. Pressing play does nothing.

**Root cause:** `AppleMusicService.setQueue()` uses `MusicCatalogResourceRequest` to look up songs by ID, but song IDs come from `MusicLibraryRequest`. Library IDs (e.g., `"i.e5gmPS6rZ856"`) and catalog IDs (numeric like `"1603171516"`) are different namespaces. The catalog lookup returns zero results, leaving the queue empty.

## Solution

### 1. Fix Playback

Change `setQueue()` to use `MusicLibraryRequest` instead of `MusicCatalogResourceRequest`:

```swift
func setQueue(songs: [Song]) async throws {
    let ids = songs.map { MusicItemID($0.id) }

    // Use library request, not catalog request
    var request = MusicLibraryRequest<MusicKit.Song>()
    request.filter(matching: \.id, memberOf: ids)
    let response = try await request.response()

    let queue = ApplicationMusicPlayer.Queue(for: response.items, startingAt: nil)
    player.queue = queue
    player.state.shuffleMode = .songs
}
```

### 2. Add Playback Time Data

Expose current playback position and song duration from `AppleMusicService`:

- `currentPlaybackTime: TimeInterval` - from `ApplicationMusicPlayer.shared.playbackTime`
- `currentSongDuration: TimeInterval` - from current song's `duration` property

Update `MusicService` protocol and `MockMusicService` accordingly.

### 3. Click Wheel UI

Circular control layout inspired by iPod shuffle:

```
        (+) Add
         |
(⏮)----[▶]----(⏭)
         |
        (-) Remove
```

**Controls:**
- **Center:** Play/pause
- **Top (+):** Add song - opens song picker
- **Bottom (-):** Remove currently playing song from collection
- **Right (⏭):** Skip to next song
- **Left (⏮):** Restart current song (authentic shuffle - no previous)

**Component structure:**
```
ClickWheelView
├── ClickWheelBackground
├── PlayPauseButton (center)
├── ControlButton (top: +)
├── ControlButton (bottom: -)
├── ControlButton (left: ⏮)
└── ControlButton (right: ⏭)
```

### 4. Progress Bar (Feature Flagged)

Display-only progress bar below the click wheel:

```
1:18 ────────●───────── 4:02
```

**Behavior:**
- No touch interaction (authentic shuffle)
- Real-time updates during playback
- Shows `--:--` / `--:--` when nothing playing

**Feature flag:**
```swift
enum FeatureFlags {
    static let showProgressBar = true
}
```

**Component structure:**
```
PlaybackProgressBar
├── ProgressTrack (background)
├── ProgressFill (filled portion)
├── TimeLabel (left: current)
└── TimeLabel (right: duration)
```

## Scope

**In scope:**
- Fix `setQueue()` to use library request
- Expose playback time from MusicService
- ClickWheelView component
- PlaybackProgressBar component (feature flagged)
- Skip back restarts current song
- Remove button removes currently playing song (with undo)

**Out of scope:**
- Scrubbing/seeking
- Previous song navigation
- Settings UI for feature flags
- Click wheel rotation gestures

## Files to Modify

| File | Changes |
|------|---------|
| `AppleMusicService.swift` | Fix setQueue, add time properties |
| `MusicService.swift` | Protocol updates for time |
| `MockMusicService.swift` | Conform to updated protocol |
| `PlayerView.swift` | Integrate click wheel and progress bar |
| `FeatureFlags.swift` | New file - feature flag constants |
| `ClickWheelView.swift` | New file - click wheel component |
| `PlaybackProgressBar.swift` | New file - progress bar component |

## Future Considerations

- Skip back/forward behavior may change (noted for future flexibility)
- Progress bar visibility toggle based on user testing
- Potential click wheel rotation gestures
