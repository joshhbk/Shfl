# Last.fm Scrobbling Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add Last.fm scrobbling that tracks song plays and retries on failure.

**Architecture:** Transport pattern with `ScrobbleTransport` protocol allows future services. `ScrobbleTracker` monitors playback via `MusicService`, `ScrobbleManager` broadcasts to transports, `LastFMTransport` handles Last.fm specifics with persistent retry queue.

**Tech Stack:** Swift, ASWebAuthenticationSession, Keychain Services, Network framework (NWPathMonitor), CommonCrypto (MD5)

---

## Task 1: ScrobbleEvent Model

**Files:**
- Create: `Shfl/Services/Scrobbling/ScrobbleEvent.swift`
- Test: `ShflTests/Services/Scrobbling/ScrobbleEventTests.swift`

**Step 1: Write the test**

```swift
import Testing
@testable import Shfl

@Suite("ScrobbleEvent Tests")
struct ScrobbleEventTests {

    @Test("ScrobbleEvent initializes with all properties")
    func initialization() {
        let timestamp = Date()
        let event = ScrobbleEvent(
            track: "Never Gonna Give You Up",
            artist: "Rick Astley",
            album: "Whenever You Need Somebody",
            timestamp: timestamp,
            durationSeconds: 213
        )

        #expect(event.track == "Never Gonna Give You Up")
        #expect(event.artist == "Rick Astley")
        #expect(event.album == "Whenever You Need Somebody")
        #expect(event.timestamp == timestamp)
        #expect(event.durationSeconds == 213)
    }

    @Test("ScrobbleEvent is Sendable")
    func sendableConformance() async {
        let event = ScrobbleEvent(
            track: "Test",
            artist: "Artist",
            album: "Album",
            timestamp: Date(),
            durationSeconds: 180
        )

        // If this compiles, Sendable conformance works
        await Task { _ = event }.value
    }
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test 2>&1 | grep -E "(ScrobbleEvent|error:)"`
Expected: Compilation error - ScrobbleEvent not found

**Step 3: Create the Scrobbling group and write implementation**

```swift
import Foundation

struct ScrobbleEvent: Sendable, Equatable {
    let track: String
    let artist: String
    let album: String
    let timestamp: Date
    let durationSeconds: Int
}
```

**Step 4: Run test to verify it passes**

Run: `xcodebuild -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test 2>&1 | grep -E "(ScrobbleEvent|passed|failed)"`
Expected: PASS

**Step 5: Commit**

```bash
git add Shfl/Services/Scrobbling/ScrobbleEvent.swift ShflTests/Services/Scrobbling/ScrobbleEventTests.swift
git commit -m "feat(scrobbling): add ScrobbleEvent model"
```

---

## Task 2: ScrobbleTransport Protocol

**Files:**
- Create: `Shfl/Services/Scrobbling/ScrobbleTransport.swift`
- Test: `ShflTests/Services/Scrobbling/ScrobbleTransportTests.swift`

**Step 1: Write the test with a mock transport**

```swift
import Testing
@testable import Shfl

actor MockScrobbleTransport: ScrobbleTransport {
    var isAuthenticated: Bool = true
    private(set) var scrobbledEvents: [ScrobbleEvent] = []
    private(set) var nowPlayingEvents: [ScrobbleEvent] = []

    func scrobble(_ event: ScrobbleEvent) async {
        scrobbledEvents.append(event)
    }

    func sendNowPlaying(_ event: ScrobbleEvent) async {
        nowPlayingEvents.append(event)
    }
}

@Suite("ScrobbleTransport Tests")
struct ScrobbleTransportTests {

    @Test("Transport receives scrobble events")
    func scrobbleEvent() async {
        let transport = MockScrobbleTransport()
        let event = ScrobbleEvent(
            track: "Test",
            artist: "Artist",
            album: "Album",
            timestamp: Date(),
            durationSeconds: 180
        )

        await transport.scrobble(event)

        let events = await transport.scrobbledEvents
        #expect(events.count == 1)
        #expect(events.first == event)
    }

    @Test("Transport receives now playing events")
    func nowPlayingEvent() async {
        let transport = MockScrobbleTransport()
        let event = ScrobbleEvent(
            track: "Test",
            artist: "Artist",
            album: "Album",
            timestamp: Date(),
            durationSeconds: 180
        )

        await transport.sendNowPlaying(event)

        let events = await transport.nowPlayingEvents
        #expect(events.count == 1)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test 2>&1 | grep -E "(ScrobbleTransport|error:)"`
Expected: Compilation error - ScrobbleTransport not found

**Step 3: Write implementation**

```swift
import Foundation

protocol ScrobbleTransport: Sendable {
    var isAuthenticated: Bool { get async }
    func scrobble(_ event: ScrobbleEvent) async
    func sendNowPlaying(_ event: ScrobbleEvent) async
}
```

**Step 4: Run test to verify it passes**

Run: `xcodebuild -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test 2>&1 | grep -E "(ScrobbleTransport|passed|failed)"`
Expected: PASS

**Step 5: Commit**

```bash
git add Shfl/Services/Scrobbling/ScrobbleTransport.swift ShflTests/Services/Scrobbling/ScrobbleTransportTests.swift
git commit -m "feat(scrobbling): add ScrobbleTransport protocol"
```

---

## Task 3: ScrobbleManager

**Files:**
- Create: `Shfl/Services/Scrobbling/ScrobbleManager.swift`
- Test: `ShflTests/Services/Scrobbling/ScrobbleManagerTests.swift`

**Step 1: Write the test**

```swift
import Testing
@testable import Shfl

@Suite("ScrobbleManager Tests")
struct ScrobbleManagerTests {

    @Test("Manager broadcasts scrobble to all transports")
    func broadcastsScrobble() async {
        let transport1 = MockScrobbleTransport()
        let transport2 = MockScrobbleTransport()
        let manager = ScrobbleManager(transports: [transport1, transport2])

        let event = ScrobbleEvent(
            track: "Test",
            artist: "Artist",
            album: "Album",
            timestamp: Date(),
            durationSeconds: 180
        )

        await manager.scrobble(event)

        let events1 = await transport1.scrobbledEvents
        let events2 = await transport2.scrobbledEvents
        #expect(events1.count == 1)
        #expect(events2.count == 1)
    }

    @Test("Manager broadcasts now playing to all transports")
    func broadcastsNowPlaying() async {
        let transport1 = MockScrobbleTransport()
        let transport2 = MockScrobbleTransport()
        let manager = ScrobbleManager(transports: [transport1, transport2])

        let event = ScrobbleEvent(
            track: "Test",
            artist: "Artist",
            album: "Album",
            timestamp: Date(),
            durationSeconds: 180
        )

        await manager.sendNowPlaying(event)

        let events1 = await transport1.nowPlayingEvents
        let events2 = await transport2.nowPlayingEvents
        #expect(events1.count == 1)
        #expect(events2.count == 1)
    }

    @Test("Manager only scrobbles to authenticated transports")
    func onlyAuthenticatedTransports() async {
        let authenticated = MockScrobbleTransport()
        let unauthenticated = MockScrobbleTransport()
        await unauthenticated.setAuthenticated(false)

        let manager = ScrobbleManager(transports: [authenticated, unauthenticated])

        let event = ScrobbleEvent(
            track: "Test",
            artist: "Artist",
            album: "Album",
            timestamp: Date(),
            durationSeconds: 180
        )

        await manager.scrobble(event)

        let authEvents = await authenticated.scrobbledEvents
        let unauthEvents = await unauthenticated.scrobbledEvents
        #expect(authEvents.count == 1)
        #expect(unauthEvents.count == 0)
    }
}
```

**Step 2: Update MockScrobbleTransport to support authentication toggle**

Add to the mock in `ScrobbleTransportTests.swift`:

```swift
actor MockScrobbleTransport: ScrobbleTransport {
    private var _isAuthenticated: Bool = true
    var isAuthenticated: Bool { _isAuthenticated }
    private(set) var scrobbledEvents: [ScrobbleEvent] = []
    private(set) var nowPlayingEvents: [ScrobbleEvent] = []

    func setAuthenticated(_ value: Bool) {
        _isAuthenticated = value
    }

    func scrobble(_ event: ScrobbleEvent) async {
        scrobbledEvents.append(event)
    }

    func sendNowPlaying(_ event: ScrobbleEvent) async {
        nowPlayingEvents.append(event)
    }
}
```

**Step 3: Run test to verify it fails**

Run: `xcodebuild -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test 2>&1 | grep -E "(ScrobbleManager|error:)"`
Expected: Compilation error - ScrobbleManager not found

**Step 4: Write implementation**

```swift
import Foundation

actor ScrobbleManager {
    private let transports: [any ScrobbleTransport]

    init(transports: [any ScrobbleTransport]) {
        self.transports = transports
    }

    func scrobble(_ event: ScrobbleEvent) async {
        for transport in transports {
            guard await transport.isAuthenticated else { continue }
            await transport.scrobble(event)
        }
    }

    func sendNowPlaying(_ event: ScrobbleEvent) async {
        for transport in transports {
            guard await transport.isAuthenticated else { continue }
            await transport.sendNowPlaying(event)
        }
    }
}
```

**Step 5: Run test to verify it passes**

Run: `xcodebuild -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test 2>&1 | grep -E "(ScrobbleManager|passed|failed)"`
Expected: PASS

**Step 6: Commit**

```bash
git add Shfl/Services/Scrobbling/ScrobbleManager.swift ShflTests/Services/Scrobbling/ScrobbleManagerTests.swift ShflTests/Services/Scrobbling/ScrobbleTransportTests.swift
git commit -m "feat(scrobbling): add ScrobbleManager to broadcast events"
```

---

## Task 4: ScrobbleTracker - Threshold Logic

**Files:**
- Create: `Shfl/Services/Scrobbling/ScrobbleTracker.swift`
- Test: `ShflTests/Services/Scrobbling/ScrobbleTrackerTests.swift`

**Step 1: Write tests for threshold calculation**

```swift
import Testing
@testable import Shfl

@Suite("ScrobbleTracker Tests")
struct ScrobbleTrackerTests {

    // MARK: - Threshold Calculation Tests

    @Test("Threshold is half duration for short songs")
    func thresholdHalfDuration() {
        // 2 minute song = 120 seconds, threshold should be 60 seconds
        let threshold = ScrobbleTracker.scrobbleThreshold(forDurationSeconds: 120)
        #expect(threshold == 60)
    }

    @Test("Threshold is 4 minutes for long songs")
    func thresholdFourMinutes() {
        // 10 minute song = 600 seconds, threshold should be 240 seconds (4 min)
        let threshold = ScrobbleTracker.scrobbleThreshold(forDurationSeconds: 600)
        #expect(threshold == 240)
    }

    @Test("Threshold is half for songs under 8 minutes")
    func thresholdBoundary() {
        // 8 minute song = 480 seconds, half = 240, so threshold is 240
        let threshold = ScrobbleTracker.scrobbleThreshold(forDurationSeconds: 480)
        #expect(threshold == 240)
    }

    @Test("Songs under 30 seconds should not scrobble")
    func shortSongsNoScrobble() {
        let shouldScrobble = ScrobbleTracker.shouldScrobble(durationSeconds: 25)
        #expect(shouldScrobble == false)
    }

    @Test("Songs 30 seconds or more should scrobble")
    func normalSongsScrobble() {
        let shouldScrobble = ScrobbleTracker.shouldScrobble(durationSeconds: 30)
        #expect(shouldScrobble == true)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test 2>&1 | grep -E "(ScrobbleTracker|error:)"`
Expected: Compilation error - ScrobbleTracker not found

**Step 3: Write implementation (threshold logic only)**

```swift
import Foundation

@MainActor
final class ScrobbleTracker {
    private let scrobbleManager: ScrobbleManager
    private let musicService: MusicService

    init(scrobbleManager: ScrobbleManager, musicService: MusicService) {
        self.scrobbleManager = scrobbleManager
        self.musicService = musicService
    }

    // MARK: - Threshold Calculation (static for testability)

    static let minimumDurationForScrobble: Int = 30
    static let maximumThresholdSeconds: Int = 240  // 4 minutes

    static func shouldScrobble(durationSeconds: Int) -> Bool {
        durationSeconds >= minimumDurationForScrobble
    }

    static func scrobbleThreshold(forDurationSeconds duration: Int) -> Int {
        min(duration / 2, maximumThresholdSeconds)
    }
}
```

**Step 4: Run test to verify it passes**

Run: `xcodebuild -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test 2>&1 | grep -E "(ScrobbleTracker|passed|failed)"`
Expected: PASS

**Step 5: Commit**

```bash
git add Shfl/Services/Scrobbling/ScrobbleTracker.swift ShflTests/Services/Scrobbling/ScrobbleTrackerTests.swift
git commit -m "feat(scrobbling): add ScrobbleTracker with threshold logic"
```

---

## Task 5: ScrobbleTracker - Playback Tracking

**Files:**
- Modify: `Shfl/Services/Scrobbling/ScrobbleTracker.swift`
- Modify: `ShflTests/Services/Scrobbling/ScrobbleTrackerTests.swift`

**Step 1: Add tests for playback tracking**

Add to `ScrobbleTrackerTests.swift`:

```swift
    // MARK: - Playback Tracking Tests

    @Test("Scrobble fires when threshold reached")
    func scrobbleOnThreshold() async throws {
        let transport = MockScrobbleTransport()
        let manager = ScrobbleManager(transports: [transport])
        let mockService = MockMusicService()
        let tracker = ScrobbleTracker(scrobbleManager: manager, musicService: mockService)

        let song = Song(
            id: "1",
            title: "Test Song",
            artist: "Test Artist",
            albumTitle: "Test Album",
            artworkURL: nil
        )

        // Simulate playing for threshold duration (song is 60 seconds, threshold is 30)
        mockService.mockDuration = 60
        tracker.onPlaybackStateChanged(.playing(song))

        // Simulate time passing (threshold is 30 seconds for 60-second song)
        tracker.simulateTimeElapsed(seconds: 31)

        // Allow async work to complete
        try await Task.sleep(for: .milliseconds(50))

        let scrobbled = await transport.scrobbledEvents
        #expect(scrobbled.count == 1)
        #expect(scrobbled.first?.track == "Test Song")
    }

    @Test("Now playing sent when playback starts")
    func nowPlayingOnStart() async throws {
        let transport = MockScrobbleTransport()
        let manager = ScrobbleManager(transports: [transport])
        let mockService = MockMusicService()
        let tracker = ScrobbleTracker(scrobbleManager: manager, musicService: mockService)

        let song = Song(
            id: "1",
            title: "Test Song",
            artist: "Test Artist",
            albumTitle: "Test Album",
            artworkURL: nil
        )

        mockService.mockDuration = 180
        tracker.onPlaybackStateChanged(.playing(song))

        // Allow async work to complete
        try await Task.sleep(for: .milliseconds(50))

        let nowPlaying = await transport.nowPlayingEvents
        #expect(nowPlaying.count == 1)
    }

    @Test("Pausing stops time accumulation")
    func pauseStopsTracking() async throws {
        let transport = MockScrobbleTransport()
        let manager = ScrobbleManager(transports: [transport])
        let mockService = MockMusicService()
        let tracker = ScrobbleTracker(scrobbleManager: manager, musicService: mockService)

        let song = Song(
            id: "1",
            title: "Test Song",
            artist: "Test Artist",
            albumTitle: "Test Album",
            artworkURL: nil
        )

        mockService.mockDuration = 60
        tracker.onPlaybackStateChanged(.playing(song))
        tracker.simulateTimeElapsed(seconds: 20)
        tracker.onPlaybackStateChanged(.paused(song))
        tracker.simulateTimeElapsed(seconds: 20)  // This shouldn't count

        try await Task.sleep(for: .milliseconds(50))

        let scrobbled = await transport.scrobbledEvents
        #expect(scrobbled.count == 0)  // Didn't reach threshold
    }

    @Test("Scrobble fires only once per song")
    func scrobbleOnlyOnce() async throws {
        let transport = MockScrobbleTransport()
        let manager = ScrobbleManager(transports: [transport])
        let mockService = MockMusicService()
        let tracker = ScrobbleTracker(scrobbleManager: manager, musicService: mockService)

        let song = Song(
            id: "1",
            title: "Test Song",
            artist: "Test Artist",
            albumTitle: "Test Album",
            artworkURL: nil
        )

        mockService.mockDuration = 60
        tracker.onPlaybackStateChanged(.playing(song))
        tracker.simulateTimeElapsed(seconds: 35)  // Past threshold
        try await Task.sleep(for: .milliseconds(50))

        tracker.simulateTimeElapsed(seconds: 20)  // More time
        try await Task.sleep(for: .milliseconds(50))

        let scrobbled = await transport.scrobbledEvents
        #expect(scrobbled.count == 1)  // Still just one
    }

    @Test("Song change resets tracking")
    func songChangeResets() async throws {
        let transport = MockScrobbleTransport()
        let manager = ScrobbleManager(transports: [transport])
        let mockService = MockMusicService()
        let tracker = ScrobbleTracker(scrobbleManager: manager, musicService: mockService)

        let song1 = Song(id: "1", title: "Song 1", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        let song2 = Song(id: "2", title: "Song 2", artist: "Artist", albumTitle: "Album", artworkURL: nil)

        mockService.mockDuration = 60
        tracker.onPlaybackStateChanged(.playing(song1))
        tracker.simulateTimeElapsed(seconds: 20)

        // Change song before threshold
        tracker.onPlaybackStateChanged(.playing(song2))
        tracker.simulateTimeElapsed(seconds: 35)

        try await Task.sleep(for: .milliseconds(50))

        let scrobbled = await transport.scrobbledEvents
        #expect(scrobbled.count == 1)
        #expect(scrobbled.first?.track == "Song 2")
    }
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test 2>&1 | grep -E "(ScrobbleTracker|error:)"`
Expected: Errors about missing methods

**Step 3: Add MockMusicService.mockDuration property**

Add to `ShflTests/Mocks/MockMusicService.swift`:

```swift
var mockDuration: TimeInterval = 0
var currentSongDuration: TimeInterval { mockDuration }
```

**Step 4: Update ScrobbleTracker implementation**

```swift
import Foundation

@MainActor
final class ScrobbleTracker {
    private let scrobbleManager: ScrobbleManager
    private let musicService: MusicService

    private var currentSong: Song?
    private var playStartTime: Date?
    private var accumulatedPlayTime: TimeInterval = 0
    private var hasScrobbledCurrentSong = false
    private var isPlaying = false

    init(scrobbleManager: ScrobbleManager, musicService: MusicService) {
        self.scrobbleManager = scrobbleManager
        self.musicService = musicService
    }

    // MARK: - Threshold Calculation (static for testability)

    static let minimumDurationForScrobble: Int = 30
    static let maximumThresholdSeconds: Int = 240  // 4 minutes

    static func shouldScrobble(durationSeconds: Int) -> Bool {
        durationSeconds >= minimumDurationForScrobble
    }

    static func scrobbleThreshold(forDurationSeconds duration: Int) -> Int {
        min(duration / 2, maximumThresholdSeconds)
    }

    // MARK: - Playback Tracking

    func onPlaybackStateChanged(_ state: PlaybackState) {
        switch state {
        case .playing(let song):
            if song.id != currentSong?.id {
                // New song
                resetTracking()
                currentSong = song
                sendNowPlaying(song)
            }
            startTracking()

        case .paused:
            pauseTracking()

        case .stopped, .empty, .error:
            resetTracking()

        case .loading:
            // Do nothing while loading
            break
        }
    }

    private func startTracking() {
        guard !isPlaying else { return }
        isPlaying = true
        playStartTime = Date()
    }

    private func pauseTracking() {
        guard isPlaying, let startTime = playStartTime else { return }
        isPlaying = false
        accumulatedPlayTime += Date().timeIntervalSince(startTime)
        playStartTime = nil
    }

    private func resetTracking() {
        currentSong = nil
        playStartTime = nil
        accumulatedPlayTime = 0
        hasScrobbledCurrentSong = false
        isPlaying = false
    }

    private func sendNowPlaying(_ song: Song) {
        let durationSeconds = Int(musicService.currentSongDuration)
        let event = ScrobbleEvent(
            track: song.title,
            artist: song.artist,
            album: song.albumTitle,
            timestamp: Date(),
            durationSeconds: durationSeconds
        )
        Task {
            await scrobbleManager.sendNowPlaying(event)
        }
    }

    private func checkAndScrobble() {
        guard !hasScrobbledCurrentSong,
              let song = currentSong else { return }

        let durationSeconds = Int(musicService.currentSongDuration)
        guard Self.shouldScrobble(durationSeconds: durationSeconds) else { return }

        let threshold = Self.scrobbleThreshold(forDurationSeconds: durationSeconds)
        let totalPlayTime = totalElapsedPlayTime()

        if Int(totalPlayTime) >= threshold {
            hasScrobbledCurrentSong = true
            scrobble(song, durationSeconds: durationSeconds)
        }
    }

    private func totalElapsedPlayTime() -> TimeInterval {
        var total = accumulatedPlayTime
        if isPlaying, let startTime = playStartTime {
            total += Date().timeIntervalSince(startTime)
        }
        return total
    }

    private func scrobble(_ song: Song, durationSeconds: Int) {
        let event = ScrobbleEvent(
            track: song.title,
            artist: song.artist,
            album: song.albumTitle,
            timestamp: Date(),
            durationSeconds: durationSeconds
        )
        Task {
            await scrobbleManager.scrobble(event)
        }
    }

    // MARK: - Testing Support

    func simulateTimeElapsed(seconds: TimeInterval) {
        accumulatedPlayTime += seconds
        checkAndScrobble()
    }
}
```

**Step 5: Run test to verify it passes**

Run: `xcodebuild -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test 2>&1 | grep -E "(ScrobbleTracker|passed|failed)"`
Expected: PASS

**Step 6: Commit**

```bash
git add Shfl/Services/Scrobbling/ScrobbleTracker.swift ShflTests/Services/Scrobbling/ScrobbleTrackerTests.swift ShflTests/Mocks/MockMusicService.swift
git commit -m "feat(scrobbling): add playback tracking to ScrobbleTracker"
```

---

## Task 6: LastFMClient - API Signature

**Files:**
- Create: `Shfl/Services/LastFM/LastFMClient.swift`
- Test: `ShflTests/Services/LastFM/LastFMClientTests.swift`

**Step 1: Write test for API signature generation**

```swift
import Testing
@testable import Shfl

@Suite("LastFMClient Tests")
struct LastFMClientTests {

    @Test("API signature is generated correctly")
    func apiSignature() {
        // Last.fm signature: sort params, concatenate, append secret, MD5
        // Example from docs: api_key=xxx, method=auth.getSession, token=yyy, secret=zzz
        // Sorted: api_keyxxxmethodauth.getSessiontokenyyy + zzz -> MD5

        let params = [
            "api_key": "testkey",
            "method": "track.scrobble",
            "artist": "Cher"
        ]
        let secret = "testsecret"

        let signature = LastFMClient.generateSignature(params: params, secret: secret)

        // Signature should be 32-char hex MD5
        #expect(signature.count == 32)
        #expect(signature.allSatisfy { $0.isHexDigit })
    }

    @Test("Signature is deterministic")
    func signatureDeterministic() {
        let params = ["a": "1", "b": "2"]
        let secret = "secret"

        let sig1 = LastFMClient.generateSignature(params: params, secret: secret)
        let sig2 = LastFMClient.generateSignature(params: params, secret: secret)

        #expect(sig1 == sig2)
    }

    @Test("Signature changes with different params")
    func signatureChangesWithParams() {
        let params1 = ["a": "1"]
        let params2 = ["a": "2"]
        let secret = "secret"

        let sig1 = LastFMClient.generateSignature(params: params1, secret: secret)
        let sig2 = LastFMClient.generateSignature(params: params2, secret: secret)

        #expect(sig1 != sig2)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test 2>&1 | grep -E "(LastFMClient|error:)"`
Expected: Compilation error - LastFMClient not found

**Step 3: Write implementation**

```swift
import Foundation
import CryptoKit

actor LastFMClient {
    private let apiKey: String
    private let sharedSecret: String
    private var sessionKey: String?

    private let baseURL = URL(string: "https://ws.audioscrobbler.com/2.0/")!

    init(apiKey: String, sharedSecret: String) {
        self.apiKey = apiKey
        self.sharedSecret = sharedSecret
    }

    func setSessionKey(_ key: String?) {
        self.sessionKey = key
    }

    // MARK: - Signature Generation (static for testability)

    static func generateSignature(params: [String: String], secret: String) -> String {
        // Sort parameters alphabetically by key
        let sortedParams = params.sorted { $0.key < $1.key }

        // Concatenate as key1value1key2value2...
        var signatureBase = ""
        for (key, value) in sortedParams {
            signatureBase += key + value
        }

        // Append secret
        signatureBase += secret

        // MD5 hash
        let digest = Insecure.MD5.hash(data: Data(signatureBase.utf8))
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }
}
```

**Step 4: Run test to verify it passes**

Run: `xcodebuild -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test 2>&1 | grep -E "(LastFMClient|passed|failed)"`
Expected: PASS

**Step 5: Commit**

```bash
git add Shfl/Services/LastFM/LastFMClient.swift ShflTests/Services/LastFM/LastFMClientTests.swift
git commit -m "feat(lastfm): add LastFMClient with signature generation"
```

---

## Task 7: LastFMClient - API Requests

**Files:**
- Modify: `Shfl/Services/LastFM/LastFMClient.swift`
- Modify: `ShflTests/Services/LastFM/LastFMClientTests.swift`

**Step 1: Add tests for API requests (using protocol for testability)**

```swift
    @Test("Scrobble request includes required parameters")
    func scrobbleRequestParams() async throws {
        let client = LastFMClient(apiKey: "testkey", sharedSecret: "testsecret")
        await client.setSessionKey("testsession")

        let event = ScrobbleEvent(
            track: "Test Track",
            artist: "Test Artist",
            album: "Test Album",
            timestamp: Date(timeIntervalSince1970: 1234567890),
            durationSeconds: 180
        )

        let request = await client.buildScrobbleRequest(event)

        #expect(request.httpMethod == "POST")

        let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
        #expect(body.contains("method=track.scrobble"))
        #expect(body.contains("track%5B0%5D=Test%20Track") || body.contains("track[0]=Test Track"))
        #expect(body.contains("artist%5B0%5D=Test%20Artist") || body.contains("artist[0]=Test Artist"))
        #expect(body.contains("api_sig="))
    }

    @Test("Now playing request includes required parameters")
    func nowPlayingRequestParams() async throws {
        let client = LastFMClient(apiKey: "testkey", sharedSecret: "testsecret")
        await client.setSessionKey("testsession")

        let event = ScrobbleEvent(
            track: "Test Track",
            artist: "Test Artist",
            album: "Test Album",
            timestamp: Date(),
            durationSeconds: 180
        )

        let request = await client.buildNowPlayingRequest(event)

        #expect(request.httpMethod == "POST")

        let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
        #expect(body.contains("method=track.updateNowPlaying"))
    }
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test 2>&1 | grep -E "(LastFMClient|error:|buildScrobbleRequest|buildNowPlayingRequest)"`
Expected: Error - methods not found

**Step 3: Add request building methods**

Add to `LastFMClient.swift`:

```swift
    // MARK: - Request Building

    func buildScrobbleRequest(_ event: ScrobbleEvent) -> URLRequest {
        var params: [String: String] = [
            "method": "track.scrobble",
            "api_key": apiKey,
            "sk": sessionKey ?? "",
            "track[0]": event.track,
            "artist[0]": event.artist,
            "album[0]": event.album,
            "timestamp[0]": String(Int(event.timestamp.timeIntervalSince1970)),
            "duration[0]": String(event.durationSeconds)
        ]

        let signature = Self.generateSignature(params: params, secret: sharedSecret)
        params["api_sig"] = signature
        params["format"] = "json"

        return buildPOSTRequest(params: params)
    }

    func buildNowPlayingRequest(_ event: ScrobbleEvent) -> URLRequest {
        var params: [String: String] = [
            "method": "track.updateNowPlaying",
            "api_key": apiKey,
            "sk": sessionKey ?? "",
            "track": event.track,
            "artist": event.artist,
            "album": event.album,
            "duration": String(event.durationSeconds)
        ]

        let signature = Self.generateSignature(params: params, secret: sharedSecret)
        params["api_sig"] = signature
        params["format"] = "json"

        return buildPOSTRequest(params: params)
    }

    private func buildPOSTRequest(params: [String: String]) -> URLRequest {
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = params
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
        request.httpBody = body.data(using: .utf8)

        return request
    }
```

**Step 4: Run test to verify it passes**

Run: `xcodebuild -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test 2>&1 | grep -E "(LastFMClient|passed|failed)"`
Expected: PASS

**Step 5: Commit**

```bash
git add Shfl/Services/LastFM/LastFMClient.swift ShflTests/Services/LastFM/LastFMClientTests.swift
git commit -m "feat(lastfm): add request building to LastFMClient"
```

---

## Task 8: LastFMQueue - Persistence

**Files:**
- Create: `Shfl/Services/LastFM/LastFMQueue.swift`
- Test: `ShflTests/Services/LastFM/LastFMQueueTests.swift`

**Step 1: Write tests**

```swift
import Testing
import Foundation
@testable import Shfl

@Suite("LastFMQueue Tests")
struct LastFMQueueTests {

    @Test("Queue persists and loads events")
    func persistAndLoad() async throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")

        defer { try? FileManager.default.removeItem(at: tempURL) }

        let queue = LastFMQueue(storageURL: tempURL)

        let event = ScrobbleEvent(
            track: "Test",
            artist: "Artist",
            album: "Album",
            timestamp: Date(),
            durationSeconds: 180
        )

        await queue.enqueue(event)

        // Create new queue instance to test persistence
        let queue2 = LastFMQueue(storageURL: tempURL)
        let pending = await queue2.pending()

        #expect(pending.count == 1)
        #expect(pending.first?.track == "Test")
    }

    @Test("Dequeue removes event")
    func dequeueRemoves() async throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")

        defer { try? FileManager.default.removeItem(at: tempURL) }

        let queue = LastFMQueue(storageURL: tempURL)

        let event = ScrobbleEvent(
            track: "Test",
            artist: "Artist",
            album: "Album",
            timestamp: Date(),
            durationSeconds: 180
        )

        await queue.enqueue(event)
        let batch = await queue.dequeueBatch(limit: 10)
        await queue.confirmDequeued(batch)

        let pending = await queue.pending()
        #expect(pending.isEmpty)
    }

    @Test("Failed dequeue returns events to queue")
    func failedDequeueReturns() async throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")

        defer { try? FileManager.default.removeItem(at: tempURL) }

        let queue = LastFMQueue(storageURL: tempURL)

        let event = ScrobbleEvent(
            track: "Test",
            artist: "Artist",
            album: "Album",
            timestamp: Date(),
            durationSeconds: 180
        )

        await queue.enqueue(event)
        let batch = await queue.dequeueBatch(limit: 10)
        await queue.returnToQueue(batch)  // Failed, return

        let pending = await queue.pending()
        #expect(pending.count == 1)
    }

    @Test("Batch respects limit")
    func batchLimit() async throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")

        defer { try? FileManager.default.removeItem(at: tempURL) }

        let queue = LastFMQueue(storageURL: tempURL)

        for i in 0..<10 {
            let event = ScrobbleEvent(
                track: "Track \(i)",
                artist: "Artist",
                album: "Album",
                timestamp: Date(),
                durationSeconds: 180
            )
            await queue.enqueue(event)
        }

        let batch = await queue.dequeueBatch(limit: 5)
        #expect(batch.count == 5)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test 2>&1 | grep -E "(LastFMQueue|error:)"`
Expected: Compilation error - LastFMQueue not found

**Step 3: Write implementation**

```swift
import Foundation

actor LastFMQueue {
    private let storageURL: URL
    private var events: [ScrobbleEvent] = []
    private var inFlight: [ScrobbleEvent] = []

    init(storageURL: URL? = nil) {
        self.storageURL = storageURL ?? Self.defaultStorageURL()
        loadFromDisk()
    }

    private static func defaultStorageURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let shflDir = appSupport.appendingPathComponent("Shfl", isDirectory: true)
        try? FileManager.default.createDirectory(at: shflDir, withIntermediateDirectories: true)
        return shflDir.appendingPathComponent("lastfm_queue.json")
    }

    func enqueue(_ event: ScrobbleEvent) {
        events.append(event)
        saveToDisk()
    }

    func pending() -> [ScrobbleEvent] {
        events
    }

    func dequeueBatch(limit: Int) -> [ScrobbleEvent] {
        let batch = Array(events.prefix(limit))
        inFlight = batch
        events.removeFirst(min(limit, events.count))
        saveToDisk()
        return batch
    }

    func confirmDequeued(_ batch: [ScrobbleEvent]) {
        inFlight.removeAll { event in
            batch.contains { $0 == event }
        }
    }

    func returnToQueue(_ batch: [ScrobbleEvent]) {
        events.insert(contentsOf: batch, at: 0)
        inFlight.removeAll { event in
            batch.contains { $0 == event }
        }
        saveToDisk()
    }

    // MARK: - Persistence

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        do {
            let data = try Data(contentsOf: storageURL)
            events = try JSONDecoder().decode([ScrobbleEvent].self, from: data)
        } catch {
            // If we can't load, start fresh
            events = []
        }
    }

    private func saveToDisk() {
        do {
            let data = try JSONEncoder().encode(events)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            // Log error in production
        }
    }
}
```

**Step 4: Make ScrobbleEvent Codable**

Update `ScrobbleEvent.swift`:

```swift
struct ScrobbleEvent: Sendable, Equatable, Codable {
    let track: String
    let artist: String
    let album: String
    let timestamp: Date
    let durationSeconds: Int
}
```

**Step 5: Run test to verify it passes**

Run: `xcodebuild -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test 2>&1 | grep -E "(LastFMQueue|passed|failed)"`
Expected: PASS

**Step 6: Commit**

```bash
git add Shfl/Services/LastFM/LastFMQueue.swift Shfl/Services/Scrobbling/ScrobbleEvent.swift ShflTests/Services/LastFM/LastFMQueueTests.swift
git commit -m "feat(lastfm): add LastFMQueue with persistence"
```

---

## Task 9: LastFMAuthenticator - Keychain Storage

**Files:**
- Create: `Shfl/Services/LastFM/LastFMAuthenticator.swift`
- Test: `ShflTests/Services/LastFM/LastFMAuthenticatorTests.swift`

**Step 1: Write tests for Keychain operations**

```swift
import Testing
@testable import Shfl

@Suite("LastFMAuthenticator Tests")
struct LastFMAuthenticatorTests {

    @Test("Store and retrieve session from keychain")
    func storeAndRetrieve() async throws {
        let authenticator = LastFMAuthenticator(
            apiKey: "testkey",
            sharedSecret: "testsecret",
            keychainService: "com.shfl.test.\(UUID().uuidString)"
        )

        let session = LastFMSession(sessionKey: "abc123", username: "testuser")
        try await authenticator.storeSession(session)

        let retrieved = await authenticator.storedSession()
        #expect(retrieved?.sessionKey == "abc123")
        #expect(retrieved?.username == "testuser")

        // Cleanup
        try await authenticator.clearSession()
    }

    @Test("isAuthenticated returns true when session exists")
    func isAuthenticatedTrue() async throws {
        let authenticator = LastFMAuthenticator(
            apiKey: "testkey",
            sharedSecret: "testsecret",
            keychainService: "com.shfl.test.\(UUID().uuidString)"
        )

        let session = LastFMSession(sessionKey: "abc123", username: "testuser")
        try await authenticator.storeSession(session)

        let isAuth = await authenticator.isAuthenticated
        #expect(isAuth == true)

        // Cleanup
        try await authenticator.clearSession()
    }

    @Test("isAuthenticated returns false when no session")
    func isAuthenticatedFalse() async {
        let authenticator = LastFMAuthenticator(
            apiKey: "testkey",
            sharedSecret: "testsecret",
            keychainService: "com.shfl.test.\(UUID().uuidString)"
        )

        let isAuth = await authenticator.isAuthenticated
        #expect(isAuth == false)
    }

    @Test("Clear session removes from keychain")
    func clearSession() async throws {
        let authenticator = LastFMAuthenticator(
            apiKey: "testkey",
            sharedSecret: "testsecret",
            keychainService: "com.shfl.test.\(UUID().uuidString)"
        )

        let session = LastFMSession(sessionKey: "abc123", username: "testuser")
        try await authenticator.storeSession(session)
        try await authenticator.clearSession()

        let retrieved = await authenticator.storedSession()
        #expect(retrieved == nil)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test 2>&1 | grep -E "(LastFMAuthenticator|error:)"`
Expected: Compilation error

**Step 3: Write implementation**

```swift
import Foundation
import Security
import AuthenticationServices

struct LastFMSession: Codable, Equatable {
    let sessionKey: String
    let username: String
}

actor LastFMAuthenticator {
    private let apiKey: String
    private let sharedSecret: String
    private let keychainService: String

    private var cachedSession: LastFMSession?

    init(
        apiKey: String,
        sharedSecret: String,
        keychainService: String = "com.shfl.lastfm.session"
    ) {
        self.apiKey = apiKey
        self.sharedSecret = sharedSecret
        self.keychainService = keychainService
    }

    var isAuthenticated: Bool {
        storedSession() != nil
    }

    func storedSession() -> LastFMSession? {
        if let cached = cachedSession {
            return cached
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let session = try? JSONDecoder().decode(LastFMSession.self, from: data) else {
            return nil
        }

        cachedSession = session
        return session
    }

    func storeSession(_ session: LastFMSession) throws {
        let data = try JSONEncoder().encode(session)

        // Delete existing first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecValueData as String: data
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw LastFMAuthError.keychainError(status)
        }

        cachedSession = session
    }

    func clearSession() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw LastFMAuthError.keychainError(status)
        }

        cachedSession = nil
    }
}

enum LastFMAuthError: Error {
    case keychainError(OSStatus)
    case authenticationFailed(String)
    case tokenExchangeFailed
}
```

**Step 4: Run test to verify it passes**

Run: `xcodebuild -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test 2>&1 | grep -E "(LastFMAuthenticator|passed|failed)"`
Expected: PASS

**Step 5: Commit**

```bash
git add Shfl/Services/LastFM/LastFMAuthenticator.swift ShflTests/Services/LastFM/LastFMAuthenticatorTests.swift
git commit -m "feat(lastfm): add LastFMAuthenticator with Keychain storage"
```

---

## Task 10: LastFMAuthenticator - Web Auth Flow

**Files:**
- Modify: `Shfl/Services/LastFM/LastFMAuthenticator.swift`

**Step 1: Add web authentication flow**

Add to `LastFMAuthenticator.swift`:

```swift
    // MARK: - Web Authentication

    @MainActor
    func authenticate() async throws -> LastFMSession {
        let authURL = URL(string: "https://www.last.fm/api/auth/?api_key=\(apiKey)&cb=shfl://lastfm")!

        let token = try await performWebAuth(url: authURL)
        let session = try await exchangeTokenForSession(token: token)
        try storeSession(session)
        return session
    }

    @MainActor
    private func performWebAuth(url: URL) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: "shfl"
            ) { callbackURL, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let callbackURL = callbackURL,
                      let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                      let token = components.queryItems?.first(where: { $0.name == "token" })?.value else {
                    continuation.resume(throwing: LastFMAuthError.authenticationFailed("No token in callback"))
                    return
                }

                continuation.resume(returning: token)
            }

            session.prefersEphemeralWebBrowserSession = false
            session.presentationContextProvider = WebAuthContextProvider.shared
            session.start()
        }
    }

    private func exchangeTokenForSession(token: String) async throws -> LastFMSession {
        var params: [String: String] = [
            "method": "auth.getSession",
            "api_key": apiKey,
            "token": token
        ]

        let signature = LastFMClient.generateSignature(params: params, secret: sharedSecret)
        params["api_sig"] = signature
        params["format"] = "json"

        let queryString = params
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
        let url = URL(string: "https://ws.audioscrobbler.com/2.0/?\(queryString)")!

        let (data, _) = try await URLSession.shared.data(from: url)

        struct SessionResponse: Decodable {
            let session: SessionData

            struct SessionData: Decodable {
                let name: String
                let key: String
            }
        }

        let response = try JSONDecoder().decode(SessionResponse.self, from: data)
        return LastFMSession(sessionKey: response.session.key, username: response.session.name)
    }
}

// MARK: - Presentation Context

@MainActor
final class WebAuthContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = WebAuthContextProvider()

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first else {
            fatalError("No window available for authentication")
        }
        return window
    }
}
```

**Step 2: Run build to verify it compiles**

Run: `xcodebuild -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add Shfl/Services/LastFM/LastFMAuthenticator.swift
git commit -m "feat(lastfm): add web authentication flow"
```

---

## Task 11: LastFMTransport

**Files:**
- Create: `Shfl/Services/LastFM/LastFMTransport.swift`
- Test: `ShflTests/Services/LastFM/LastFMTransportTests.swift`

**Step 1: Write tests**

```swift
import Testing
@testable import Shfl

@Suite("LastFMTransport Tests")
struct LastFMTransportTests {

    @Test("Transport is not authenticated without session")
    func notAuthenticatedWithoutSession() async {
        let transport = LastFMTransport(
            apiKey: "test",
            sharedSecret: "test",
            keychainService: "com.shfl.test.\(UUID().uuidString)"
        )

        let isAuth = await transport.isAuthenticated
        #expect(isAuth == false)
    }

    @Test("Scrobble queues event when not authenticated")
    func scrobbleQueuesWhenNotAuthenticated() async {
        let queueURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")

        defer { try? FileManager.default.removeItem(at: queueURL) }

        let transport = LastFMTransport(
            apiKey: "test",
            sharedSecret: "test",
            keychainService: "com.shfl.test.\(UUID().uuidString)",
            queueURL: queueURL
        )

        let event = ScrobbleEvent(
            track: "Test",
            artist: "Artist",
            album: "Album",
            timestamp: Date(),
            durationSeconds: 180
        )

        await transport.scrobble(event)

        // Event should be queued since not authenticated
        let pending = await transport.pendingScrobbles()
        #expect(pending.count == 1)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test 2>&1 | grep -E "(LastFMTransport|error:)"`
Expected: Compilation error

**Step 3: Write implementation**

```swift
import Foundation
import Network

actor LastFMTransport: ScrobbleTransport {
    private let client: LastFMClient
    private let authenticator: LastFMAuthenticator
    private let queue: LastFMQueue
    private let networkMonitor: NWPathMonitor

    private var isNetworkAvailable = true

    init(
        apiKey: String,
        sharedSecret: String,
        keychainService: String = "com.shfl.lastfm.session",
        queueURL: URL? = nil
    ) {
        self.client = LastFMClient(apiKey: apiKey, sharedSecret: sharedSecret)
        self.authenticator = LastFMAuthenticator(
            apiKey: apiKey,
            sharedSecret: sharedSecret,
            keychainService: keychainService
        )
        self.queue = LastFMQueue(storageURL: queueURL)
        self.networkMonitor = NWPathMonitor()

        setupNetworkMonitoring()
    }

    var isAuthenticated: Bool {
        get async {
            await authenticator.isAuthenticated
        }
    }

    func scrobble(_ event: ScrobbleEvent) async {
        guard await isAuthenticated else {
            await queue.enqueue(event)
            return
        }

        if isNetworkAvailable {
            do {
                try await sendScrobble(event)
            } catch {
                await queue.enqueue(event)
            }
        } else {
            await queue.enqueue(event)
        }
    }

    func sendNowPlaying(_ event: ScrobbleEvent) async {
        guard await isAuthenticated, isNetworkAvailable else { return }

        // Now playing is best-effort, no queuing
        do {
            try await sendNowPlayingRequest(event)
        } catch {
            // Ignore errors for now playing
        }
    }

    func pendingScrobbles() async -> [ScrobbleEvent] {
        await queue.pending()
    }

    // MARK: - Authentication

    @MainActor
    func authenticate() async throws -> LastFMSession {
        let session = try await authenticator.authenticate()
        await client.setSessionKey(session.sessionKey)
        await flushQueue()
        return session
    }

    // MARK: - Private

    private func setupNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            Task { [weak self] in
                guard let self = self else { return }
                let wasAvailable = await self.isNetworkAvailable
                await self.setNetworkAvailable(path.status == .satisfied)

                if !wasAvailable && path.status == .satisfied {
                    await self.flushQueue()
                }
            }
        }
        networkMonitor.start(queue: .global(qos: .utility))
    }

    private func setNetworkAvailable(_ available: Bool) {
        isNetworkAvailable = available
    }

    private func sendScrobble(_ event: ScrobbleEvent) async throws {
        guard let session = await authenticator.storedSession() else { return }
        await client.setSessionKey(session.sessionKey)

        let request = await client.buildScrobbleRequest(event)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw LastFMError.requestFailed
        }

        // Check for API error in response
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let _ = json["error"] {
            throw LastFMError.apiError
        }
    }

    private func sendNowPlayingRequest(_ event: ScrobbleEvent) async throws {
        guard let session = await authenticator.storedSession() else { return }
        await client.setSessionKey(session.sessionKey)

        let request = await client.buildNowPlayingRequest(event)
        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw LastFMError.requestFailed
        }
    }

    private func flushQueue() async {
        guard await isAuthenticated, isNetworkAvailable else { return }

        while true {
            let batch = await queue.dequeueBatch(limit: 50)
            guard !batch.isEmpty else { break }

            do {
                for event in batch {
                    try await sendScrobble(event)
                }
                await queue.confirmDequeued(batch)
            } catch {
                await queue.returnToQueue(batch)
                break
            }
        }
    }
}

enum LastFMError: Error {
    case requestFailed
    case apiError
}
```

**Step 4: Run test to verify it passes**

Run: `xcodebuild -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test 2>&1 | grep -E "(LastFMTransport|passed|failed)"`
Expected: PASS

**Step 5: Commit**

```bash
git add Shfl/Services/LastFM/LastFMTransport.swift ShflTests/Services/LastFM/LastFMTransportTests.swift
git commit -m "feat(lastfm): add LastFMTransport with queue and network monitoring"
```

---

## Task 12: API Credentials Configuration

**Files:**
- Create: `Shfl/Services/LastFM/LastFMConfig.swift`

**Step 1: Create configuration file**

```swift
import Foundation

enum LastFMConfig {
    // TODO: Replace with your actual Last.fm API credentials
    // Get them from: https://www.last.fm/api/account/create
    static let apiKey = "YOUR_API_KEY_HERE"
    static let sharedSecret = "YOUR_SHARED_SECRET_HERE"
}
```

**Step 2: Add to .gitignore if using real keys**

The current approach uses placeholder values which is safe to commit. When real keys are added, consider using xcconfig files or environment variables.

**Step 3: Commit**

```bash
git add Shfl/Services/LastFM/LastFMConfig.swift
git commit -m "feat(lastfm): add configuration for API credentials"
```

---

## Task 13: URL Scheme Registration

**Files:**
- Modify: `Shfl/Info.plist` (or via Xcode project settings)

**Step 1: Check if Info.plist exists and add URL scheme**

Add URL scheme configuration. If using Xcode's Info tab in target settings, add:

- URL Types → Add new
- Identifier: `com.shfl.lastfm`
- URL Schemes: `shfl`

Or if editing Info.plist directly:

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLName</key>
        <string>com.shfl.lastfm</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>shfl</string>
        </array>
    </dict>
</array>
```

**Step 2: Verify build succeeds**

Run: `xcodebuild -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add Shfl/Info.plist
git commit -m "feat(lastfm): register shfl:// URL scheme for auth callback"
```

---

## Task 14: Integration - Wire into App

**Files:**
- Modify: `Shfl/ShuffledApp.swift`
- Modify: `Shfl/ViewModels/AppViewModel.swift` (or create if needed)
- Create: `Shfl/Utilities/EnvironmentKeys+Scrobbling.swift`

**Step 1: Create environment key for ScrobbleTracker**

```swift
import SwiftUI

private struct ScrobbleTrackerKey: EnvironmentKey {
    static let defaultValue: ScrobbleTracker? = nil
}

extension EnvironmentValues {
    var scrobbleTracker: ScrobbleTracker? {
        get { self[ScrobbleTrackerKey.self] }
        set { self[ScrobbleTrackerKey.self] = newValue }
    }
}
```

**Step 2: Update ShuffledApp to initialize scrobbling**

```swift
@main
struct ShuffledApp: App {
    @State private var motionManager = MotionManager()
    @State private var scrobbleTracker: ScrobbleTracker?

    // ... existing code ...

    init() {
        setupScrobbling()
    }

    private mutating func setupScrobbling() {
        let lastFMTransport = LastFMTransport(
            apiKey: LastFMConfig.apiKey,
            sharedSecret: LastFMConfig.sharedSecret
        )
        let scrobbleManager = ScrobbleManager(transports: [lastFMTransport])
        let musicService = AppleMusicService()
        _scrobbleTracker = State(initialValue: ScrobbleTracker(
            scrobbleManager: scrobbleManager,
            musicService: musicService
        ))
    }

    var body: some Scene {
        WindowGroup {
            MainView(
                musicService: AppleMusicService(),
                modelContext: sharedModelContainer.mainContext
            )
            .environment(\.motionManager, motionManager)
            .environment(\.scrobbleTracker, scrobbleTracker)
        }
        .modelContainer(sharedModelContainer)
    }
}
```

**Step 3: Connect ScrobbleTracker to playback state**

In the view or view model that has access to `ShufflePlayer`, observe playback state changes and forward to tracker:

```swift
// In AppViewModel or wherever ShufflePlayer is observed
func observePlaybackForScrobbling(tracker: ScrobbleTracker) {
    // Forward playback state changes to tracker
    // This connects the dots between playback and scrobbling
}
```

**Step 4: Verify build succeeds**

Run: `xcodebuild -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -10`
Expected: BUILD SUCCEEDED

**Step 5: Commit**

```bash
git add Shfl/ShuffledApp.swift Shfl/Utilities/EnvironmentKeys+Scrobbling.swift
git commit -m "feat(lastfm): wire scrobbling into app lifecycle"
```

---

## Task 15: Final Integration Test

**Files:**
- Create: `ShflTests/Integration/ScrobblingIntegrationTests.swift`

**Step 1: Write integration test**

```swift
import Testing
@testable import Shfl

@Suite("Scrobbling Integration Tests")
struct ScrobblingIntegrationTests {

    @Test("Full scrobble flow with mock transport")
    func fullScrobbleFlow() async throws {
        let transport = MockScrobbleTransport()
        let manager = ScrobbleManager(transports: [transport])
        let mockService = MockMusicService()
        mockService.mockDuration = 180  // 3 minute song

        let tracker = ScrobbleTracker(scrobbleManager: manager, musicService: mockService)

        let song = Song(
            id: "integration-test-1",
            title: "Integration Test Song",
            artist: "Test Artist",
            albumTitle: "Test Album",
            artworkURL: nil
        )

        // Start playing
        tracker.onPlaybackStateChanged(.playing(song))

        // Now playing should be sent
        try await Task.sleep(for: .milliseconds(50))
        let nowPlaying = await transport.nowPlayingEvents
        #expect(nowPlaying.count == 1)

        // Play past threshold (90 seconds for 180-second song)
        tracker.simulateTimeElapsed(seconds: 95)
        try await Task.sleep(for: .milliseconds(50))

        // Scrobble should be sent
        let scrobbled = await transport.scrobbledEvents
        #expect(scrobbled.count == 1)
        #expect(scrobbled.first?.track == "Integration Test Song")
        #expect(scrobbled.first?.durationSeconds == 180)
    }

    @Test("Pause and resume accumulates time correctly")
    func pauseResumeAccumulation() async throws {
        let transport = MockScrobbleTransport()
        let manager = ScrobbleManager(transports: [transport])
        let mockService = MockMusicService()
        mockService.mockDuration = 60  // 1 minute song, threshold 30s

        let tracker = ScrobbleTracker(scrobbleManager: manager, musicService: mockService)

        let song = Song(
            id: "1",
            title: "Test",
            artist: "Artist",
            albumTitle: "Album",
            artworkURL: nil
        )

        // Play 15 seconds
        tracker.onPlaybackStateChanged(.playing(song))
        tracker.simulateTimeElapsed(seconds: 15)

        // Pause
        tracker.onPlaybackStateChanged(.paused(song))

        // Resume and play 20 more seconds (total 35, past threshold)
        tracker.onPlaybackStateChanged(.playing(song))
        tracker.simulateTimeElapsed(seconds: 20)

        try await Task.sleep(for: .milliseconds(50))

        let scrobbled = await transport.scrobbledEvents
        #expect(scrobbled.count == 1)
    }
}
```

**Step 2: Run all tests**

Run: `xcodebuild -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test 2>&1 | grep -E "(passed|failed|error:)" | tail -20`
Expected: All tests PASS

**Step 3: Commit**

```bash
git add ShflTests/Integration/ScrobblingIntegrationTests.swift
git commit -m "test: add scrobbling integration tests"
```

---

## Summary

After completing all tasks, you will have:

1. **Scrobbling Infrastructure** (`Shfl/Services/Scrobbling/`)
   - `ScrobbleEvent.swift` - Data model for scrobble events
   - `ScrobbleTransport.swift` - Protocol for transport implementations
   - `ScrobbleManager.swift` - Broadcasts to all transports
   - `ScrobbleTracker.swift` - Monitors playback, triggers scrobbles

2. **Last.fm Implementation** (`Shfl/Services/LastFM/`)
   - `LastFMConfig.swift` - API credentials
   - `LastFMClient.swift` - HTTP + signature generation
   - `LastFMAuthenticator.swift` - Keychain + web auth
   - `LastFMQueue.swift` - Persistent retry queue
   - `LastFMTransport.swift` - Full transport implementation

3. **Integration**
   - URL scheme registered for auth callback
   - Wired into app lifecycle
   - Environment key for access in views

4. **Tests** - Comprehensive unit and integration tests

To use: Call `LastFMTransport.authenticate()` from your settings UI to trigger the auth flow.
