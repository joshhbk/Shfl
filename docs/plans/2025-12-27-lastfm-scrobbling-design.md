# Last.fm Scrobbling Integration Design

## Overview

Add Last.fm scrobbling support to Shuffled, allowing users to track their listening history on Last.fm. The implementation uses a transport pattern to support future scrobbling services.

## Scope

- **In scope:** Scrobbling plays, "now playing" updates, retry queue, authentication
- **Out of scope:** UI for connecting/disconnecting (handled separately in settings), fetching Last.fm user data

## Architecture

### Transport Pattern

A generic abstraction allows multiple scrobbling services:

```swift
protocol ScrobbleTransport: Sendable {
    var isAuthenticated: Bool { get }
    func scrobble(_ event: ScrobbleEvent) async
    func sendNowPlaying(_ event: ScrobbleEvent) async
}

struct ScrobbleEvent: Sendable {
    let track: String
    let artist: String
    let album: String
    let timestamp: Date
    let duration: Int
}
```

### File Structure

```
Shfl/Services/
├── Scrobbling/
│   ├── ScrobbleTransport.swift   # Protocol definition
│   ├── ScrobbleManager.swift     # Broadcasts to all transports
│   ├── ScrobbleEvent.swift       # Shared event model
│   └── ScrobbleTracker.swift     # Monitors playback, triggers scrobbles
│
├── LastFM/
│   ├── LastFMTransport.swift     # ScrobbleTransport implementation
│   ├── LastFMClient.swift        # HTTP layer + signature generation
│   ├── LastFMAuthenticator.swift # ASWebAuthenticationSession + Keychain
│   └── LastFMQueue.swift         # Persistent retry queue
```

### Component Responsibilities

| Component | Responsibility |
|-----------|----------------|
| `ScrobbleTransport` | Protocol abstraction for any scrobbling service |
| `ScrobbleManager` | Holds registered transports, broadcasts scrobble events to all |
| `ScrobbleTracker` | Monitors playback state, fires scrobbles when threshold met |
| `LastFMTransport` | Last.fm implementation of ScrobbleTransport |
| `LastFMClient` | Raw HTTP requests, MD5 signature generation |
| `LastFMAuthenticator` | Web auth flow, Keychain storage for session key |
| `LastFMQueue` | Persists failed scrobbles to disk, retries on connectivity |

## Scrobbling Logic

### When to Scrobble

Per Last.fm's official rules:
- Track must be longer than 30 seconds
- Track has played for at least half its duration OR 4 minutes (whichever comes first)

### ScrobbleTracker Flow

```swift
func onPlaybackStateChanged(_ state: PlaybackState) {
    switch state {
    case .playing(let song):
        sendNowPlaying(song)
        startTrackingPlaytime(song)
    case .paused:
        pauseTracking()
    case .stopped, .empty:
        resetTracking()
    }
}
```

The tracker:
1. Starts a timer when a song begins playing
2. Pauses the timer when playback pauses
3. Fires a scrobble (once) when threshold is reached
4. Resets when the song changes or stops

## Retry Queue

### Storage

- JSON file in Application Support directory
- Lightweight, no SwiftData dependency needed

### Data Model

```swift
struct PendingScrobble: Codable {
    let track: String
    let artist: String
    let album: String
    let timestamp: Date
    let duration: Int
}
```

### Retry Strategy

- On failure: add to queue, persist immediately
- On app launch: flush queue if authenticated
- On network restoration: listen via `NWPathMonitor`, flush when connectivity returns
- Exponential backoff if Last.fm is consistently failing
- Last.fm accepts batch scrobbles (up to 50), so retries are efficient

## Authentication

### Flow

1. Open `ASWebAuthenticationSession` to `https://www.last.fm/api/auth/?api_key=XXX&cb=shfl://lastfm`
2. User grants permission on Last.fm website
3. Last.fm redirects to `shfl://lastfm?token=XXX`
4. App exchanges token for session key via `auth.getSession` API
5. Store session key + username in Keychain

### Keychain Storage

- Key identifier: `com.shfl.lastfm.session`
- Stores: session key, username
- Persists across app reinstalls

### URL Scheme

- Register `shfl://` in Info.plist (if not already present)
- Handle `shfl://lastfm?token=XXX` callback

## API Details

### Credentials

- `api_key` and `shared_secret` as compile-time constants
- Session key stored in Keychain (the sensitive credential)

### Request Signing

Last.fm requires an `api_sig` on every request:
1. Sort all parameters alphabetically by key
2. Concatenate as `key1value1key2value2...`
3. Append shared secret
4. MD5 hash the result

### Endpoints

- Base URL: `https://ws.audioscrobbler.com/2.0/`
- `track.scrobble` — Submit played tracks (supports batching up to 50)
- `track.updateNowPlaying` — Update "now playing" status
- `auth.getSession` — Exchange auth token for session key

## Integration Points

- `ScrobbleManager` initialized in `ShuffledApp` or `AppViewModel`
- `ScrobbleTracker` observes playback state from `ShufflePlayer`
- `LastFMTransport` registered with `ScrobbleManager` on app launch
- Future: settings UI calls `LastFMAuthenticator` to trigger auth flow

## Testing

- Mock `ScrobbleTransport` for unit testing `ScrobbleTracker`
- Mock `LastFMClient` for testing `LastFMTransport` retry logic
- Integration tests against Last.fm sandbox (if available) or real API with test account
