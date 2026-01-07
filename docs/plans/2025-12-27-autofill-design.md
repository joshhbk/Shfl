# Autofill Feature - Design Document

An Autofill button that instantly fills remaining shuffle slots with random songs from the user's Apple Music library.

## Overview

**Inspiration:** iTunes Autofill for iPod shuffle - one tap to fill your device with music.

**MVP Behavior:**
- Fills remaining slots (keeps existing songs)
- Random selection from user's Apple Music library
- Skips songs already in the shuffle (no duplicates)
- Immediate action with brief confirmation feedback

## Architecture

### Strategy Pattern for Extensibility

```swift
protocol AutofillSource {
    func fetchSongs(excluding: [Song], limit: Int) async throws -> [Song]
}

struct LibraryAutofillSource: AutofillSource {
    let musicService: MusicService

    func fetchSongs(excluding: [Song], limit: Int) async throws -> [Song] {
        // Fetch random songs from library, excluding duplicates
    }
}

// Future: PlaylistAutofillSource, FavoritesAutofillSource, etc.
```

This keeps autofill logic decoupled from the source - adding playlist-based autofill later is just a new conforming type.

## Data Flow

```
User taps Autofill
       ↓
SongPickerView calls LibraryBrowserViewModel.autofill()
       ↓
AutofillSource fetches random songs (excluding current shuffle)
       ↓
Songs added via existing SongRepository.add()
       ↓
UI shows confirmation ("Added 47 songs")
```

### Integration Points

1. **MusicService protocol** - needs method to fetch random songs from library
2. **SongRepository** - reuse existing `add()` for persisting songs
3. **LibraryBrowserViewModel** - coordinates autofill flow and loading state

## UI Design

### SongPickerView Layout

```
┌─────────────────────────────────────────┐
│ Autofill          Add songs        Done │  <- Autofill button top-left
├─────────────────────────────────────────┤
│ Search songs...                         │
├─────────────────────────────────────────┤
│ [Song rows...]                          │
└─────────────────────────────────────────┘
```

### Button States

| State | Appearance |
|-------|------------|
| Available (slots remaining) | Enabled, normal text |
| Full (120 songs) | Disabled, dimmed |
| Loading (fetching songs) | Disabled, shows spinner |

### Feedback

Brief confirmation banner ("Added 47 songs") that auto-dismisses after ~2 seconds.

## Error Handling

| Scenario | Handling |
|----------|----------|
| No Apple Music authorization | Show existing auth prompt flow |
| Network error during fetch | Show brief error banner, user can retry |
| Library is empty | Show "Added 0 songs" |
| All library songs already in shuffle | Show "Added 0 songs" |

No special error states - feature degrades gracefully.

## Testing

- `AutofillSource` protocol enables easy mocking
- Unit tests for `LibraryAutofillSource`: duplicate exclusion, limit handling, empty library
- Unit tests for ViewModel: loading states, button enabled/disabled logic
- Integration test: end-to-end autofill flow with `MockMusicService`

## Future Extensibility

Designed for but not implemented:

| Future Feature | How Strategy Pattern Supports It |
|----------------|----------------------------------|
| Playlist source | New `PlaylistAutofillSource` conforming type |
| Replace all mode | Add `AutofillMode` enum parameter to fill method |
| Prefer higher rated | Add weighting logic inside source implementation |
| Multiple sources | Compose sources or add source picker UI |

## Open Questions

None at this time.
