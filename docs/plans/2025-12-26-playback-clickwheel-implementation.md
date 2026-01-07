# Playback Fix & Click Wheel Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix broken Apple Music playback and implement click wheel-style player controls with optional progress bar.

**Architecture:** Fix `setQueue()` to use `MusicLibraryRequest` instead of `MusicCatalogResourceRequest`. Add playback time tracking. Create composable `ClickWheelView` and `PlaybackProgressBar` components.

**Tech Stack:** SwiftUI, MusicKit, XCTest

---

### Task 1: Fix setQueue() to Use Library Request

**Files:**
- Modify: `Shfl/Services/AppleMusicService.swift:128-137`

**Step 1: Update setQueue implementation**

Replace the current `setQueue` method:

```swift
func setQueue(songs: [Song]) async throws {
    let ids = songs.map { MusicItemID($0.id) }

    // Use MusicLibraryRequest instead of MusicCatalogResourceRequest
    var request = MusicLibraryRequest<MusicKit.Song>()
    request.filter(matching: \.id, memberOf: ids)
    let response = try await request.response()

    guard !response.items.isEmpty else {
        return
    }

    let queue = ApplicationMusicPlayer.Queue(for: response.items, startingAt: nil)
    player.queue = queue
    player.state.shuffleMode = .songs
}
```

**Step 2: Test manually on device**

Run on device with Apple Music library. Add songs, press play. Verify music plays.

**Step 3: Commit**

```bash
git add Shfl/Services/AppleMusicService.swift
git commit -m "fix: use MusicLibraryRequest in setQueue for correct ID lookup"
```

---

### Task 2: Add Playback Time Properties to Protocol

**Files:**
- Modify: `Shfl/Domain/Protocols/MusicService.swift`
- Modify: `Shfl/Services/AppleMusicService.swift`
- Modify: `ShflTests/Mocks/MockMusicService.swift`
- Modify: `Shfl/Services/MockMusicService.swift` (app mock)

**Step 1: Update MusicService protocol**

Add to `MusicService.swift` after `playbackStateStream`:

```swift
/// Current playback time in seconds
var currentPlaybackTime: TimeInterval { get }

/// Duration of current song in seconds (0 if nothing playing)
var currentSongDuration: TimeInterval { get }
```

**Step 2: Implement in AppleMusicService**

Add to `AppleMusicService.swift` after `playbackStateStream`:

```swift
var currentPlaybackTime: TimeInterval {
    player.playbackTime
}

var currentSongDuration: TimeInterval {
    guard let entry = player.queue.currentEntry,
          case .song(let song) = entry.item,
          let duration = song.duration else {
        return 0
    }
    return duration
}
```

**Step 3: Implement in test MockMusicService**

Add to `ShflTests/Mocks/MockMusicService.swift` after `playbackStateStream`:

```swift
var mockPlaybackTime: TimeInterval = 0
var mockSongDuration: TimeInterval = 0

nonisolated var currentPlaybackTime: TimeInterval {
    0  // Will use mockPlaybackTime via helper
}

nonisolated var currentSongDuration: TimeInterval {
    0  // Will use mockSongDuration via helper
}
```

Actually, since it's an actor, add these as stored properties with getters:

```swift
private var _currentPlaybackTime: TimeInterval = 0
private var _currentSongDuration: TimeInterval = 180  // 3 min default

nonisolated var currentPlaybackTime: TimeInterval { 0 }
nonisolated var currentSongDuration: TimeInterval { 180 }

func setPlaybackTime(_ time: TimeInterval) {
    _currentPlaybackTime = time
}

func setSongDuration(_ duration: TimeInterval) {
    _currentSongDuration = duration
}
```

**Step 4: Implement in app MockMusicService**

Add to `Shfl/Services/MockMusicService.swift` (similar pattern).

**Step 5: Commit**

```bash
git add Shfl/Domain/Protocols/MusicService.swift Shfl/Services/AppleMusicService.swift ShflTests/Mocks/MockMusicService.swift Shfl/Services/MockMusicService.swift
git commit -m "feat: add currentPlaybackTime and currentSongDuration to MusicService"
```

---

### Task 3: Add skipToPrevious to MusicService

**Files:**
- Modify: `Shfl/Domain/Protocols/MusicService.swift`
- Modify: `Shfl/Services/AppleMusicService.swift`
- Modify: `ShflTests/Mocks/MockMusicService.swift`
- Modify: `Shfl/Services/MockMusicService.swift`

**Step 1: Add protocol method**

Add to `MusicService.swift`:

```swift
/// Restart current song from beginning
func restartCurrentSong() async throws
```

**Step 2: Implement in AppleMusicService**

```swift
func restartCurrentSong() async throws {
    player.playbackTime = 0
}
```

**Step 3: Implement in both MockMusicService files**

```swift
func restartCurrentSong() async throws {
    // No-op for mock
}
```

**Step 4: Add to ShufflePlayer**

Add to `Shfl/Domain/ShufflePlayer.swift`:

```swift
func restartCurrentSong() async throws {
    try await musicService.restartCurrentSong()
}
```

**Step 5: Commit**

```bash
git add Shfl/Domain/Protocols/MusicService.swift Shfl/Services/AppleMusicService.swift ShflTests/Mocks/MockMusicService.swift Shfl/Services/MockMusicService.swift Shfl/Domain/ShufflePlayer.swift
git commit -m "feat: add restartCurrentSong to MusicService"
```

---

### Task 4: Create FeatureFlags

**Files:**
- Create: `Shfl/FeatureFlags.swift`

**Step 1: Create FeatureFlags file**

```swift
import Foundation

enum FeatureFlags {
    /// Show progress bar below click wheel
    static let showProgressBar = true
}
```

**Step 2: Commit**

```bash
git add Shfl/FeatureFlags.swift
git commit -m "feat: add FeatureFlags with showProgressBar toggle"
```

---

### Task 5: Create ClickWheelButton Component

**Files:**
- Create: `Shfl/Views/Components/ClickWheelButton.swift`

**Step 1: Create the component**

```swift
import SwiftUI

struct ClickWheelButton: View {
    let systemName: String
    let action: () -> Void

    @State private var tapCount = 0

    var body: some View {
        Button(action: {
            tapCount += 1
            action()
        }) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color(white: 0.3))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .light), trigger: tapCount)
    }
}

#Preview {
    HStack(spacing: 20) {
        ClickWheelButton(systemName: "plus") {}
        ClickWheelButton(systemName: "minus") {}
        ClickWheelButton(systemName: "backward.end.fill") {}
        ClickWheelButton(systemName: "forward.end.fill") {}
    }
    .padding()
    .background(Color.gray.opacity(0.2))
}
```

**Step 2: Commit**

```bash
git add Shfl/Views/Components/ClickWheelButton.swift
git commit -m "feat: add ClickWheelButton component"
```

---

### Task 6: Create ClickWheelView Component

**Files:**
- Create: `Shfl/Views/Components/ClickWheelView.swift`

**Step 1: Create the component**

```swift
import SwiftUI

struct ClickWheelView: View {
    let isPlaying: Bool
    let onPlayPause: () -> Void
    let onSkipForward: () -> Void
    let onSkipBack: () -> Void
    let onAdd: () -> Void
    let onRemove: () -> Void

    private let wheelSize: CGFloat = 280
    private let centerButtonSize: CGFloat = 80

    var body: some View {
        ZStack {
            // Outer wheel background
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.95), Color(white: 0.88)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: wheelSize, height: wheelSize)
                .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 6)

            // Control buttons positioned around the wheel
            VStack {
                ClickWheelButton(systemName: "plus", action: onAdd)
                Spacer()
            }
            .frame(height: wheelSize - 40)

            VStack {
                Spacer()
                ClickWheelButton(systemName: "minus", action: onRemove)
            }
            .frame(height: wheelSize - 40)

            HStack {
                ClickWheelButton(systemName: "backward.end.fill", action: onSkipBack)
                Spacer()
            }
            .frame(width: wheelSize - 40)

            HStack {
                Spacer()
                ClickWheelButton(systemName: "forward.end.fill", action: onSkipForward)
            }
            .frame(width: wheelSize - 40)

            // Center play/pause button
            PlayPauseButton(isPlaying: isPlaying, action: onPlayPause)
        }
    }
}

#Preview("Paused") {
    ClickWheelView(
        isPlaying: false,
        onPlayPause: {},
        onSkipForward: {},
        onSkipBack: {},
        onAdd: {},
        onRemove: {}
    )
    .padding()
    .background(Color(red: 0.8, green: 0.2, blue: 0.3))
}

#Preview("Playing") {
    ClickWheelView(
        isPlaying: true,
        onPlayPause: {},
        onSkipForward: {},
        onSkipBack: {},
        onAdd: {},
        onRemove: {}
    )
    .padding()
    .background(Color(red: 0.8, green: 0.2, blue: 0.3))
}
```

**Step 2: Commit**

```bash
git add Shfl/Views/Components/ClickWheelView.swift
git commit -m "feat: add ClickWheelView component"
```

---

### Task 7: Create PlaybackProgressBar Component

**Files:**
- Create: `Shfl/Views/Components/PlaybackProgressBar.swift`

**Step 1: Create the component**

```swift
import SwiftUI

struct PlaybackProgressBar: View {
    let currentTime: TimeInterval
    let duration: TimeInterval

    private var progress: Double {
        guard duration > 0 else { return 0 }
        return min(currentTime / duration, 1.0)
    }

    var body: some View {
        VStack(spacing: 8) {
            // Progress track
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track
                    Capsule()
                        .fill(Color.white.opacity(0.3))
                        .frame(height: 4)

                    // Filled track
                    Capsule()
                        .fill(Color.white)
                        .frame(width: geometry.size.width * progress, height: 4)
                }
            }
            .frame(height: 4)

            // Time labels
            HStack {
                Text(formatTime(currentTime))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))

                Spacer()

                Text(formatTime(duration))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        guard time.isFinite && time >= 0 else {
            return "--:--"
        }
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

#Preview {
    VStack(spacing: 40) {
        PlaybackProgressBar(currentTime: 78, duration: 242)
        PlaybackProgressBar(currentTime: 0, duration: 180)
        PlaybackProgressBar(currentTime: 0, duration: 0)
    }
    .padding(32)
    .background(Color(red: 0.8, green: 0.2, blue: 0.3))
}
```

**Step 2: Commit**

```bash
git add Shfl/Views/Components/PlaybackProgressBar.swift
git commit -m "feat: add PlaybackProgressBar component"
```

---

### Task 8: Update PlayerView with Click Wheel

**Files:**
- Modify: `Shfl/Views/PlayerView.swift`

**Step 1: Replace controls with ClickWheelView**

Replace the entire `PlayerView` with updated version that:
1. Uses `ClickWheelView` instead of separate buttons
2. Adds `PlaybackProgressBar` (behind feature flag)
3. Adds timer for progress updates
4. Handles remove current song with undo

```swift
import SwiftUI

struct PlayerView: View {
    @ObservedObject var player: ShufflePlayer
    let musicService: MusicService
    let onManageTapped: () -> Void
    let onAddTapped: () -> Void

    @State private var showError = false
    @State private var errorMessage = ""
    @State private var currentTime: TimeInterval = 0
    @State private var duration: TimeInterval = 0
    @State private var progressTimer: Timer?
    @State private var removedSong: Song?
    @State private var showUndoPill = false

    init(
        player: ShufflePlayer,
        musicService: MusicService,
        onManageTapped: @escaping () -> Void,
        onAddTapped: @escaping () -> Void = {}
    ) {
        self.player = player
        self.musicService = musicService
        self.onManageTapped = onManageTapped
        self.onAddTapped = onAddTapped
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                backgroundGradient

                VStack(spacing: 0) {
                    // Error banner at top
                    if showError {
                        ErrorBanner(message: errorMessage) {
                            withAnimation {
                                showError = false
                            }
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    topBar(geometry: geometry)

                    Spacer()

                    VStack(spacing: 32) {
                        nowPlayingSection

                        ClickWheelView(
                            isPlaying: player.playbackState.isPlaying,
                            onPlayPause: handlePlayPause,
                            onSkipForward: handleSkipForward,
                            onSkipBack: handleSkipBack,
                            onAdd: onAddTapped,
                            onRemove: handleRemove
                        )
                        .disabled(player.songCount == 0)
                        .opacity(player.songCount == 0 ? 0.6 : 1.0)

                        if FeatureFlags.showProgressBar {
                            PlaybackProgressBar(
                                currentTime: currentTime,
                                duration: duration
                            )
                            .padding(.horizontal, 40)
                        }
                    }

                    Spacer()

                    Button(action: onManageTapped) {
                        Text("View Library")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .padding(.bottom, geometry.safeAreaInsets.bottom + 24)
                }

                // Undo pill
                if showUndoPill, let song = removedSong {
                    VStack {
                        Spacer()
                        UndoPill(
                            message: "Removed \"\(song.title)\"",
                            onUndo: handleUndo
                        )
                        .padding(.bottom, geometry.safeAreaInsets.bottom + 60)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.2), value: showError)
            .animation(.easeInOut(duration: 0.2), value: showUndoPill)
            .onChange(of: player.playbackState) { _, newState in
                handlePlaybackStateChange(newState)
            }
            .onAppear {
                startProgressTimer()
            }
            .onDisappear {
                stopProgressTimer()
            }
        }
    }

    @ViewBuilder
    private func topBar(geometry: GeometryProxy) -> some View {
        HStack {
            Spacer()
            CapacityIndicator(current: player.songCount, maximum: player.capacity)
            Spacer()
        }
        .padding(.top, showError ? 16 : geometry.safeAreaInsets.top + 16)
    }

    @ViewBuilder
    private var nowPlayingSection: some View {
        switch player.playbackState {
        case .loading(let song):
            VStack(spacing: 12) {
                ProgressView()
                    .scaleEffect(1.2)
                    .tint(.white)
                NowPlayingInfo(title: song.title, artist: song.artist)
                    .opacity(0.7)
            }
            .transition(.opacity)
        case .playing(let song), .paused(let song):
            NowPlayingInfo(title: song.title, artist: song.artist)
                .transition(.opacity)
        default:
            emptyStateView
        }
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(red: 0.75, green: 0.22, blue: 0.32),
                Color(red: 0.65, green: 0.18, blue: 0.28)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Text("No songs yet")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)

            Text("Add some music to get started")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    // MARK: - Actions

    private func handlePlayPause() {
        Task {
            try? await player.togglePlayback()
        }
    }

    private func handleSkipForward() {
        Task {
            try? await player.skipToNext()
        }
    }

    private func handleSkipBack() {
        Task {
            try? await player.restartCurrentSong()
        }
    }

    private func handleRemove() {
        guard let currentSong = player.playbackState.currentSong else { return }

        removedSong = currentSong
        player.removeSong(id: currentSong.id)

        withAnimation {
            showUndoPill = true
        }

        // Auto-hide after 5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            withAnimation {
                showUndoPill = false
            }
        }
    }

    private func handleUndo() {
        guard let song = removedSong else { return }
        try? player.addSong(song)
        removedSong = nil
        withAnimation {
            showUndoPill = false
        }
    }

    private func handlePlaybackStateChange(_ newState: PlaybackState) {
        if case .error(let error) = newState {
            errorMessage = error.localizedDescription
            withAnimation {
                showError = true
            }
        }

        // Update duration when song changes
        duration = musicService.currentSongDuration
    }

    // MARK: - Progress Timer

    private func startProgressTimer() {
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            currentTime = musicService.currentPlaybackTime
            duration = musicService.currentSongDuration
        }
    }

    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }
}

private final class PreviewMockMusicService: MusicService, @unchecked Sendable {
    var isAuthorized: Bool { true }
    var currentPlaybackTime: TimeInterval { 78 }
    var currentSongDuration: TimeInterval { 242 }
    var playbackStateStream: AsyncStream<PlaybackState> {
        AsyncStream { continuation in
            continuation.yield(.empty)
        }
    }
    func requestAuthorization() async -> Bool { true }
    func prefetchLibrary() async {}
    func fetchLibrarySongs(sortedBy: SortOption, limit: Int, offset: Int) async throws -> LibraryPage {
        LibraryPage(songs: [], hasMore: false)
    }
    func searchLibrarySongs(query: String) async throws -> [Song] { [] }
    func setQueue(songs: [Song]) async throws {}
    func play() async throws {}
    func pause() async {}
    func skipToNext() async throws {}
    func restartCurrentSong() async throws {}
}

#Preview("Empty State") {
    let mockService = PreviewMockMusicService()
    let player = ShufflePlayer(musicService: mockService)
    return PlayerView(
        player: player,
        musicService: mockService,
        onManageTapped: {},
        onAddTapped: {}
    )
}

#Preview("Playing") {
    let mockService = PreviewMockMusicService()
    let player = ShufflePlayer(musicService: mockService)
    return PlayerView(
        player: player,
        musicService: mockService,
        onManageTapped: {},
        onAddTapped: {}
    )
}
```

**Step 2: Commit**

```bash
git add Shfl/Views/PlayerView.swift
git commit -m "feat: integrate ClickWheelView and PlaybackProgressBar into PlayerView"
```

---

### Task 9: Update MainView to Pass MusicService

**Files:**
- Modify: `Shfl/Views/MainView.swift`

**Step 1: Update PlayerView call to include musicService**

In `MainView.swift`, update the `PlayerView` instantiation:

```swift
PlayerView(
    player: viewModel.player,
    musicService: viewModel.musicService,
    onManageTapped: { viewModel.openManage() },
    onAddTapped: { viewModel.openPickerDirect() }
)
```

**Step 2: Commit**

```bash
git add Shfl/Views/MainView.swift
git commit -m "feat: pass musicService to PlayerView for progress tracking"
```

---

### Task 10: Update NowPlayingInfo for New Theme

**Files:**
- Modify: `Shfl/Views/Components/NowPlayingInfo.swift`

**Step 1: Update colors for red background**

The text needs to be white/light for the new red gradient background:

```swift
import SwiftUI

struct NowPlayingInfo: View {
    let title: String
    let artist: String

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            Text(artist)
                .font(.system(size: 16))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(1)
        }
    }
}

#Preview {
    NowPlayingInfo(title: "Song Title", artist: "Artist Name")
        .padding()
        .background(Color(red: 0.75, green: 0.22, blue: 0.32))
}
```

**Step 2: Commit**

```bash
git add Shfl/Views/Components/NowPlayingInfo.swift
git commit -m "feat: update NowPlayingInfo colors for red theme"
```

---

### Task 11: Update CapacityIndicator for New Theme

**Files:**
- Modify: `Shfl/Views/Components/CapacityIndicator.swift`

**Step 1: Check current implementation and update for white text**

Update to use white/light colors:

```swift
// Update foregroundStyle to .white or .white.opacity(0.9)
```

**Step 2: Commit**

```bash
git add Shfl/Views/Components/CapacityIndicator.swift
git commit -m "feat: update CapacityIndicator colors for red theme"
```

---

### Task 12: Build and Test

**Step 1: Build project**

```bash
xcodebuild -project Shfl.xcodeproj -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 16' build
```

**Step 2: Run tests**

```bash
xcodebuild -project Shfl.xcodeproj -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 16' test
```

**Step 3: Fix any compilation errors**

Address any issues found.

**Step 4: Manual test on device**

- Launch app
- Add songs from library
- Press play - verify music plays
- Press skip forward - verify skips
- Press skip back - verify restarts song
- Press minus - verify removes song with undo
- Verify progress bar updates (if enabled)

**Step 5: Final commit if any fixes needed**

```bash
git add -A
git commit -m "fix: address build and test issues"
```
