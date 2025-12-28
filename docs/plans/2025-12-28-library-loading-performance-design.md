# Library Loading Performance Design

## Problem

The app currently prefetches up to 1000 songs from the user's library on startup, blocking interactivity. For users with large libraries (10k+ songs), this causes unacceptable delays before the app becomes usable.

Additionally:
- Pagination is fake (loads all songs, then slices)
- Search only works against the in-memory cache (max 1000 songs)
- Users with large libraries can't access their full collection

## Goals

1. App is interactive immediately on launch (play persisted queue)
2. Library browse loads incrementally (true pagination)
3. Search queries the full library regardless of size
4. Remove startup blocking entirely

## Design

### Startup Changes

Remove the `prefetchLibrary()` call from `AppViewModel.onAppear()`. The app loads the persisted queue from SwiftData (local disk I/O, milliseconds) and becomes interactive immediately.

Library loading happens lazily when the user opens the song picker.

### True Pagination for Browse

Replace the current "fetch all, slice" pattern with MusicKit's native pagination:

```swift
func fetchLibrarySongs(
    sortedBy: SortOption,
    limit: Int,
    offset: Int
) async throws -> LibraryPage {
    var request = MusicLibraryRequest<MusicKit.Song>()
    request.limit = limit
    request.offset = offset

    switch sortedBy {
    case .mostPlayed:
        request.sort(by: \.playCount, ascending: false)
    case .recentlyPlayed:
        request.sort(by: \.lastPlayedDate, ascending: false)
    case .recentlyAdded:
        request.sort(by: \.libraryAddedDate, ascending: false)
    case .alphabetical:
        request.sort(by: \.title, ascending: true)
    }

    let response = try await request.response()
    let songs = response.items.map { /* mapping */ }
    let hasMore = response.items.count == limit

    return LibraryPage(songs: songs, hasMore: hasMore)
}
```

Each page fetches only what it needs regardless of scroll depth.

### Direct MusicKit Search

Replace in-memory cache filtering with `MusicLibrarySearchRequest`:

```swift
func searchLibrarySongs(query: String) async throws -> [Song] {
    var request = MusicLibrarySearchRequest(term: query, types: [MusicKit.Song.self])
    request.limit = 50

    let response = try await request.response()

    return response.songs.map { musicKitSong in
        Song(
            id: musicKitSong.id.rawValue,
            title: musicKitSong.title,
            artist: musicKitSong.artistName,
            albumTitle: musicKitSong.albumTitle ?? "",
            artworkURL: nil
        )
    }
}
```

This searches the user's entire library via MusicKit's index.

### Cache Removal

Remove entirely:
- `cachedLibrary: [SortOption: [Song]]`
- `prefetchTask: Task<Void, Never>?`
- `prefetchLibrary()` method
- `fetchAllLibrarySongs(sortedBy:)` method

### Sort Order Changes

When the user changes sort order, reset and reload:
- Clear the current list
- Show skeleton loading state
- Fetch first page with new sort option

## Files Affected

| File | Changes |
|------|---------|
| `AppleMusicService.swift` | Remove cache, rewrite fetch/search methods |
| `MusicService.swift` | Remove `prefetchLibrary()` from protocol |
| `MockMusicService.swift` | Update to match protocol changes |
| `AppViewModel.swift` | Remove prefetch call from `onAppear()` |

## What Stays the Same

- All playback logic
- Persisted queue loading via SwiftData
- UI components (skeleton, song rows, etc.)
- Pagination UX in LibraryBrowserViewModel

## Tradeoffs

- **Search matching**: Uses MusicKit's logic, not custom. If we want fuzzy search or custom weighting later, we'd need a local cache.
- **Offline**: Browse/search require MusicKit access. Could add local caching later for offline support.

## Future Considerations

- Hybrid approach: Cache song metadata locally for instant search, use MusicKit for browse
- Offline support via persisted library cache
- Cursor-based pagination if offset approach has issues at scale
