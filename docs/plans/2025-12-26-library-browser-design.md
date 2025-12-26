# Library Browser Design

## Overview

Replace the current Apple Music catalog search with a user library browser. When pressing the + button, users see their own library sorted by most played, with search filtering their library instead of searching globally.

## Requirements

- Browse user's library sorted by most played (with architecture to support future sort options)
- Two modes: browse (paginated list) and search (dedicated library search)
- Inline transition between modes as user types
- Paginated loading (50 songs at a time)
- Skeleton placeholder rows during loading

## Architecture

```
┌─────────────────────────────────────────┐
│            SongPickerView               │
│  ┌─────────────────────────────────┐    │
│  │    LibraryBrowserViewModel      │    │
│  │  - browseState                  │    │
│  │  - searchState                  │    │
│  │  - currentMode: .browse/.search │    │
│  └─────────────────────────────────┘    │
│                  │                      │
│     ┌────────────┴────────────┐         │
│     ▼                         ▼         │
│  Browse Mode              Search Mode   │
│  (MusicLibraryRequest)    (MusicLibrarySearchRequest)
│  - sorted by playCount    - by search term
│  - paginated              - limited results
└─────────────────────────────────────────┘
```

## Protocol Changes

### New Types

```swift
enum SortOption {
    case mostPlayed
    case recentlyPlayed
    case recentlyAdded
    case alphabetical
}

struct LibraryPage {
    let songs: [Song]
    let hasMore: Bool
    let totalCount: Int?
}
```

### Updated MusicService Protocol

```swift
protocol MusicService {
    // Existing methods...
    var isAuthorized: Bool { get async }
    var playbackStateStream: AsyncStream<PlaybackState> { get }
    func requestAuthorization() async -> Bool
    func setQueue(songs: [Song]) async throws
    func play() async throws
    func pause() async
    func skipToNext() async throws

    // New library methods (replacing searchLibrary)
    func fetchLibrarySongs(
        sortedBy: SortOption,
        limit: Int,
        offset: Int
    ) async throws -> LibraryPage

    func searchLibrarySongs(query: String) async throws -> [Song]
}
```

## AppleMusicService Implementation

### fetchLibrarySongs

Uses `MusicLibraryRequest<Song>` with sorting and pagination:

```swift
func fetchLibrarySongs(
    sortedBy: SortOption,
    limit: Int,
    offset: Int
) async throws -> LibraryPage {
    var request = MusicLibraryRequest<Song>()

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

    request.limit = limit
    request.offset = offset

    let response = try await request.response()
    // Map to Song models and return LibraryPage
}
```

### searchLibrarySongs

Uses `MusicLibrarySearchRequest`:

```swift
func searchLibrarySongs(query: String) async throws -> [Song] {
    let request = MusicLibrarySearchRequest(term: query, types: [MusicKit.Song.self])
    let response = try await request.response()
    // Map to Song models
}
```

## LibraryBrowserViewModel

```swift
@MainActor
final class LibraryBrowserViewModel: ObservableObject {
    enum Mode { case browse, search }

    // Browse state
    @Published private(set) var browseSongs: [Song] = []
    @Published private(set) var browseLoading: Bool = false
    @Published private(set) var hasMorePages: Bool = true
    @Published var sortOption: SortOption = .mostPlayed

    // Search state
    @Published private(set) var searchResults: [Song] = []
    @Published private(set) var searchLoading: Bool = false

    // Shared
    @Published var searchText: String = ""
    var currentMode: Mode { searchText.isEmpty ? .browse : .search }

    // Pagination
    private let pageSize = 50
    private var currentOffset = 0

    func loadInitialPage() async { ... }
    func loadNextPageIfNeeded(currentSong: Song) async { ... }
    func performSearch() async { ... }  // debounced 300ms
}
```

## View Changes

### SongPickerView

- Owns `LibraryBrowserViewModel` as `@StateObject`
- Switches between `browseList` and `searchList` based on `currentMode`
- Calls `loadInitialPage()` on `.task`
- Uses `.searchable(text: $viewModel.searchText)`

### SkeletonSongRow (New Component)

- Matches `SongRow` dimensions
- Gray placeholder shapes with shimmer animation
- Shows 8-10 rows during loading states

## File Changes

### Modified Files

| File | Changes |
|------|---------|
| `MusicService.swift` | Add `SortOption`, `LibraryPage`, new protocol methods |
| `AppleMusicService.swift` | Implement `fetchLibrarySongs`, `searchLibrarySongs` |
| `MockMusicService.swift` | Add matching mock implementations |
| `SongPickerView.swift` | Integrate `LibraryBrowserViewModel`, update UI |

### New Files

| File | Purpose |
|------|---------|
| `ViewModels/LibraryBrowserViewModel.swift` | Browse/search state, pagination logic |
| `Views/Components/SkeletonSongRow.swift` | Loading placeholder component |

## Implementation Order

1. Protocol & types (`SortOption`, `LibraryPage` in `MusicService.swift`)
2. `AppleMusicService` implementation
3. `MockMusicService` for testing
4. `SkeletonSongRow` component
5. `LibraryBrowserViewModel`
6. Wire up `SongPickerView`
7. Update tests

## Future Considerations

- Sort option picker UI (segmented control or menu)
- Caching library data to reduce API calls
- Album artwork prefetching for smoother scrolling
