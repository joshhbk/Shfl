# Shuffled

An iOS music player that connects to your Apple Music library and offers advanced shuffle algorithms, queue management, and an iPod Shuffle-inspired interface.

## Features

- **5 shuffle algorithms** — Pure Random, Full Shuffle, Least Recent, Least Played, and Artist Spacing (avoids back-to-back songs from the same artist)
- **Library browsing** — Browse and search by songs, artists, or playlists with pagination
- **Queue management** — Add/remove songs, bulk operations, undo support, and a visual capacity indicator
- **Session persistence** — Queue and playback state restore on app relaunch via SwiftData
- **Last.fm scrobbling** — Track listening history with offline retry queue
- **Theming** — 5 iPod Shuffle-inspired color themes with album art color extraction and tinting
- **Autofill** — Automatically populate the queue when songs run low
- **Alternate app icons**

## Requirements

- iOS 18.6+
- Xcode 16+
- An Apple Music subscription (for library access)

## Getting Started

1. Clone the repo
2. Open `Shfl.xcodeproj` in Xcode
3. Build and run on a simulator or device
4. Grant Apple Music library access when prompted

No SPM dependencies — the project uses only Apple frameworks (MusicKit, SwiftUI, SwiftData).

## Project Structure

```
Shfl/
├── Domain/          # Models, protocols, queue/playback logic
├── Services/        # AppleMusicService, Last.fm, scrobbling, artwork cache
├── ViewModels/      # AppViewModel, coordinators, library browser
├── Views/           # SwiftUI views and components
├── Theme/           # Color themes, blending, tinted theme provider
├── Data/            # SwiftData persistence (songs, playback state)
└── Utilities/       # Haptics, volume control, color extraction
```

## Architecture

- **State management** — `@Observable` with `@ObservationIgnored` for non-UI state. No Combine.
- **Immutable queue state** — `QueueState` mutations return new instances, applied through a reducer in `ShufflePlayer`
- **Service abstraction** — `MusicService` protocol enables mock implementations for previews and tests
- **Transport sync** — Domain queue state syncs to MusicKit's transport queue via revision-gated commands with rollback on failure
- **Environment injection** — App settings, theme, and service dependencies flow through SwiftUI `@Environment`

## Testing

```bash
xcodebuild test \
  -scheme Shfl \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:ShflTests
```

## License

Private. All rights reserved.
