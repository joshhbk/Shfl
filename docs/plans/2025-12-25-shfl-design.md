# Shfl - Design Document

A minimal iOS music player inspired by the iPod shuffle. Limited capacity, shuffle-only playback, distraction-free listening.

## Overview

**Core concept:** Add up to 120 songs from Apple Music, press play, and let the shuffle decide. No queues, no playlists, no decisions. Just music.

**Target platform:** iOS (SwiftUI + Swift)

**Music source:** Apple Music (MusicKit)

## Tech Stack

- **UI:** SwiftUI
- **Language:** Swift
- **Music integration:** MusicKit framework
- **Persistence:** Local storage (SwiftData or UserDefaults)
- **Backend:** None (iCloud sync as future option)

## Architecture

```
+-------------------------------------------+
|              SwiftUI Views                |  <- UI Layer
+-------------------------------------------+
|             ShufflePlayer                 |  <- App Logic (platform-agnostic)
|   (play, pause, skip, shuffle, limit)     |
+-------------------------------------------+
|          MusicService Protocol            |  <- Abstraction
+-------------------------------------------+
|      AppleMusicService (MusicKit)         |  <- Concrete Implementation
+-------------------------------------------+
```

**Key principle:** `ShufflePlayer` contains all business logic and knows nothing about MusicKit. It communicates through a `MusicService` protocol. This allows:
- Unit testing without Apple dependencies
- Future expansion to a full-featured player
- Potential alternative music sources

## State Machine

Playback state is modeled as a state machine, not booleans:

```swift
enum PlaybackState {
    case empty           // No songs in shuffle yet
    case stopped         // Has songs, not playing
    case loading(Song)   // Buffering/preparing track
    case playing(Song)   // Actively playing
    case paused(Song)    // Paused mid-track
    case error(Error)    // Something went wrong
}
```

**Valid transitions:**
- `empty` -> `stopped` (user adds first song)
- `stopped` -> `loading` (user hits play)
- `loading` -> `playing` (track ready)
- `loading` -> `error` (failed to load)
- `playing` -> `paused` (user pauses)
- `paused` -> `playing` (user resumes)
- `playing` -> `loading` (skip to next)
- `playing` -> `stopped` (queue exhausted)
- `*` -> `empty` (user removes all songs)

## Core Features (MVP)

### User Journey

1. **First launch** - Apple Music authorization prompt
2. **Empty state** - "Add songs to your shuffle" with add button
3. **Song picker** - Search/browse Apple Music library, add up to 120 songs
4. **Main screen** - Minimal player: play/pause, skip, current song
5. **Manage mode** - View collection, remove songs, add new ones

### Playback Controls

| Action | Supported |
|--------|-----------|
| Play/Pause | Yes |
| Skip forward | Yes |
| Skip back | No (authentic shuffle) |
| Scrub within track | No |
| View queue | No |
| Shuffle toggle | No (always shuffle) |

### Constraints (The Features)

- **120 song limit** - Mimics 512MB iPod shuffle capacity
- **No queue visibility** - You don't know what's next
- **Always shuffle** - No sequential playback option
- **Capacity indicator** - "47/120 songs" displayed

## UI Design

**Aesthetic:** iPod shuffle-inspired, minimal, tactile

### Main Player Screen
- Clean background (album art or abstract gradient)
- Circular button arrangement (center: play/pause, sides: skip)
- Current song title + artist (minimal text)
- Capacity indicator ("47/120")
- Optional subtle LED-style playback indicator

### Design Principles
- No tabs, navigation bars, or hamburger menus
- Feels like *the device*, not an app
- Swipe or single button to access song management
- iPod color palette (whites/silvers, or classic shuffle colors)

### Interactions
- Tactile feedback on button presses
- Smooth transitions between songs
- Button-based controls (not click wheel for MVP)

## Data Model

### Persistence
- Store song selections as Apple Music track IDs
- Local storage only (SwiftData or UserDefaults)
- Array of up to 120 `MusicItemID` values

### App State
```swift
struct ShuffleState {
    var selectedSongs: [MusicItemID]  // max 120
    var playbackState: PlaybackState
    var shuffledQueue: [Song]         // regenerated each session
}
```

## MusicKit Integration

### Required Capabilities
- `MusicLibraryRequest` - Browse user's library
- `ApplicationMusicPlayer` - Playback control
- Authorization handling

### Error Handling
- No subscription - Show message + link to subscribe
- Song unavailable - Skip automatically, optionally remove from collection
- Network offline - Graceful message, disable playback

## Future Considerations

### Stretch Goals
- Click wheel interaction for volume or collection browsing
- Classic iPod color themes
- Haptic feedback

### Expansion Path
- iCloud sync for multi-device
- Full Apple Music player (remove shuffle constraints)
- Additional "modes" (workout, road trip, etc.)

## Open Questions

None at this time.
