# Theme Switcher Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add swipeable iPod Shuffle 4th gen color themes with random selection on launch.

**Architecture:** Theme model with environment-based propagation. Horizontal drag gesture on PlayerView with slide transition. Bounded carousel with rubber-band bounce at edges.

**Tech Stack:** SwiftUI, @Environment, DragGesture, spring animations

---

## Task 1: Create ShuffleTheme Model

**Files:**
- Create: `Shfl/Theme/ShuffleTheme.swift`
- Test: `ShflTests/Theme/ShuffleThemeTests.swift`

**Step 1: Write failing tests**

Create `ShflTests/Theme/ShuffleThemeTests.swift`:

```swift
import XCTest
@testable import Shfl

final class ShuffleThemeTests: XCTestCase {

    func testAllThemesHaveUniqueIds() {
        let ids = ShuffleTheme.allThemes.map { $0.id }
        let uniqueIds = Set(ids)
        XCTAssertEqual(ids.count, uniqueIds.count, "All theme IDs should be unique")
    }

    func testAllThemesCount() {
        XCTAssertEqual(ShuffleTheme.allThemes.count, 5, "Should have 5 themes")
    }

    func testSilverHasDarkWheelStyle() {
        XCTAssertEqual(ShuffleTheme.silver.wheelStyle, .dark)
    }

    func testSilverHasDarkTextStyle() {
        XCTAssertEqual(ShuffleTheme.silver.textStyle, .dark)
    }

    func testColorfulThemesHaveLightWheelStyle() {
        let colorfulThemes = [ShuffleTheme.blue, .green, .orange, .pink]
        for theme in colorfulThemes {
            XCTAssertEqual(theme.wheelStyle, .light, "\(theme.name) should have light wheel")
        }
    }

    func testColorfulThemesHaveLightTextStyle() {
        let colorfulThemes = [ShuffleTheme.blue, .green, .orange, .pink]
        for theme in colorfulThemes {
            XCTAssertEqual(theme.textStyle, .light, "\(theme.name) should have light text")
        }
    }

    func testRandomThemeReturnsValidTheme() {
        for _ in 0..<20 {
            let theme = ShuffleTheme.random()
            XCTAssertTrue(ShuffleTheme.allThemes.contains { $0.id == theme.id })
        }
    }
}
```

**Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:ShflTests/ShuffleThemeTests 2>&1 | xcpretty`

Expected: FAIL - "Cannot find 'ShuffleTheme' in scope"

**Step 3: Create the Theme directory**

Run: `mkdir -p Shfl/Theme`

**Step 4: Write ShuffleTheme implementation**

Create `Shfl/Theme/ShuffleTheme.swift`:

```swift
import SwiftUI

struct ShuffleTheme: Identifiable, Equatable {
    let id: String
    let name: String
    let bodyGradientTop: Color
    let bodyGradientBottom: Color
    let wheelStyle: WheelStyle
    let textStyle: TextStyle

    enum WheelStyle: Equatable {
        case light
        case dark
    }

    enum TextStyle: Equatable {
        case light
        case dark
    }

    var bodyGradient: LinearGradient {
        LinearGradient(
            colors: [bodyGradientTop, bodyGradientBottom],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    var textColor: Color {
        switch textStyle {
        case .light: return .white
        case .dark: return Color(white: 0.15)
        }
    }

    var secondaryTextColor: Color {
        switch textStyle {
        case .light: return .white.opacity(0.8)
        case .dark: return Color(white: 0.15).opacity(0.7)
        }
    }
}

// MARK: - Theme Definitions

extension ShuffleTheme {
    static let silver = ShuffleTheme(
        id: "silver",
        name: "Silver",
        bodyGradientTop: Color(red: 0.75, green: 0.75, blue: 0.75),
        bodyGradientBottom: Color(red: 0.66, green: 0.66, blue: 0.66),
        wheelStyle: .dark,
        textStyle: .dark
    )

    static let blue = ShuffleTheme(
        id: "blue",
        name: "Blue",
        bodyGradientTop: Color(red: 0.29, green: 0.61, blue: 0.85),
        bodyGradientBottom: Color(red: 0.23, green: 0.48, blue: 0.69),
        wheelStyle: .light,
        textStyle: .light
    )

    static let green = ShuffleTheme(
        id: "green",
        name: "Green",
        bodyGradientTop: Color(red: 0.48, green: 0.71, blue: 0.28),
        bodyGradientBottom: Color(red: 0.35, green: 0.59, blue: 0.19),
        wheelStyle: .light,
        textStyle: .light
    )

    static let orange = ShuffleTheme(
        id: "orange",
        name: "Orange",
        bodyGradientTop: Color(red: 0.96, green: 0.65, blue: 0.14),
        bodyGradientBottom: Color(red: 0.83, green: 0.53, blue: 0.04),
        wheelStyle: .light,
        textStyle: .light
    )

    static let pink = ShuffleTheme(
        id: "pink",
        name: "Pink",
        bodyGradientTop: Color(red: 0.91, green: 0.35, blue: 0.44),
        bodyGradientBottom: Color(red: 0.77, green: 0.29, blue: 0.38),
        wheelStyle: .light,
        textStyle: .light
    )

    static let allThemes: [ShuffleTheme] = [.silver, .blue, .green, .orange, .pink]

    static func random() -> ShuffleTheme {
        allThemes.randomElement() ?? .pink
    }
}
```

**Step 5: Add files to Xcode project**

The files need to be in the project. If using Xcode's file system auto-discovery, they should appear. Otherwise add manually.

**Step 6: Run tests to verify they pass**

Run: `xcodebuild test -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:ShflTests/ShuffleThemeTests 2>&1 | xcpretty`

Expected: All 7 tests PASS

**Step 7: Commit**

```bash
git add Shfl/Theme/ShuffleTheme.swift ShflTests/Theme/ShuffleThemeTests.swift
git commit -m "feat: add ShuffleTheme model with 5 iPod Shuffle colors"
```

---

## Task 2: Create Theme Environment

**Files:**
- Create: `Shfl/Theme/ThemeEnvironment.swift`

**Step 1: Write ThemeEnvironment**

Create `Shfl/Theme/ThemeEnvironment.swift`:

```swift
import SwiftUI

private struct ShuffleThemeKey: EnvironmentKey {
    static let defaultValue: ShuffleTheme = .pink
}

extension EnvironmentValues {
    var shuffleTheme: ShuffleTheme {
        get { self[ShuffleThemeKey.self] }
        set { self[ShuffleThemeKey.self] = newValue }
    }
}
```

**Step 2: Verify build succeeds**

Run: `xcodebuild build -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | xcpretty`

Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add Shfl/Theme/ThemeEnvironment.swift
git commit -m "feat: add ShuffleTheme environment key"
```

---

## Task 3: Update ClickWheelView for Theme Support

**Files:**
- Modify: `Shfl/Views/Components/ClickWheelView.swift`

**Step 1: Update ClickWheelView to read theme from environment**

Replace `Shfl/Views/Components/ClickWheelView.swift`:

```swift
import SwiftUI

struct ClickWheelView: View {
    @Environment(\.shuffleTheme) private var theme

    let isPlaying: Bool
    let onPlayPause: () -> Void
    let onSkipForward: () -> Void
    let onSkipBack: () -> Void
    let onAdd: () -> Void
    let onRemove: () -> Void

    private let wheelSize: CGFloat = 280
    private let centerButtonSize: CGFloat = 80

    private var wheelGradient: LinearGradient {
        switch theme.wheelStyle {
        case .light:
            return LinearGradient(
                colors: [Color(white: 0.95), Color(white: 0.88)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .dark:
            return LinearGradient(
                colors: [Color(white: 0.25), Color(white: 0.15)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    var body: some View {
        ZStack {
            // Outer wheel background
            Circle()
                .fill(wheelGradient)
                .frame(width: wheelSize, height: wheelSize)
                .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 6)

            // Control buttons positioned around the wheel
            VStack {
                ClickWheelButton(systemName: "plus", action: onAdd, wheelStyle: theme.wheelStyle)
                Spacer()
            }
            .frame(height: wheelSize - 40)

            VStack {
                Spacer()
                ClickWheelButton(systemName: "minus", action: onRemove, wheelStyle: theme.wheelStyle)
            }
            .frame(height: wheelSize - 40)

            HStack {
                ClickWheelButton(systemName: "backward.end.fill", action: onSkipBack, wheelStyle: theme.wheelStyle)
                Spacer()
            }
            .frame(width: wheelSize - 40)

            HStack {
                Spacer()
                ClickWheelButton(systemName: "forward.end.fill", action: onSkipForward, wheelStyle: theme.wheelStyle)
            }
            .frame(width: wheelSize - 40)

            // Center play/pause button
            PlayPauseButton(isPlaying: isPlaying, action: onPlayPause, wheelStyle: theme.wheelStyle)
        }
    }
}

#Preview("Light Wheel - Paused") {
    ClickWheelView(
        isPlaying: false,
        onPlayPause: {},
        onSkipForward: {},
        onSkipBack: {},
        onAdd: {},
        onRemove: {}
    )
    .padding()
    .background(ShuffleTheme.pink.bodyGradient)
    .environment(\.shuffleTheme, .pink)
}

#Preview("Dark Wheel - Playing") {
    ClickWheelView(
        isPlaying: true,
        onPlayPause: {},
        onSkipForward: {},
        onSkipBack: {},
        onAdd: {},
        onRemove: {}
    )
    .padding()
    .background(ShuffleTheme.silver.bodyGradient)
    .environment(\.shuffleTheme, .silver)
}
```

**Step 2: Verify build succeeds**

Run: `xcodebuild build -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | xcpretty`

Expected: FAIL - ClickWheelButton and PlayPauseButton don't accept wheelStyle yet

---

## Task 4: Update ClickWheelButton for Theme Support

**Files:**
- Modify: `Shfl/Views/Components/ClickWheelButton.swift`

**Step 1: Read current ClickWheelButton**

First, read the current implementation to understand what to modify.

**Step 2: Update ClickWheelButton to accept wheelStyle**

Modify `Shfl/Views/Components/ClickWheelButton.swift` to add wheelStyle parameter:

```swift
import SwiftUI

struct ClickWheelButton: View {
    let systemName: String
    let action: () -> Void
    var wheelStyle: ShuffleTheme.WheelStyle = .light

    private var iconColor: Color {
        switch wheelStyle {
        case .light: return Color(white: 0.3)
        case .dark: return Color(white: 0.7)
        }
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 44, height: 44)
        }
    }
}

#Preview {
    HStack(spacing: 20) {
        ClickWheelButton(systemName: "plus", action: {}, wheelStyle: .light)
            .background(Color(white: 0.9))
        ClickWheelButton(systemName: "plus", action: {}, wheelStyle: .dark)
            .background(Color(white: 0.2))
    }
    .padding()
}
```

**Step 3: Verify build succeeds**

Run: `xcodebuild build -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | xcpretty`

Expected: FAIL - PlayPauseButton doesn't accept wheelStyle yet

---

## Task 5: Update PlayPauseButton for Theme Support

**Files:**
- Modify: `Shfl/Views/Components/PlayPauseButton.swift`

**Step 1: Read current PlayPauseButton**

First, read the current implementation.

**Step 2: Update PlayPauseButton to accept wheelStyle**

Modify `Shfl/Views/Components/PlayPauseButton.swift` to add wheelStyle parameter with appropriate colors for light/dark wheel.

**Step 3: Verify build succeeds**

Run: `xcodebuild build -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | xcpretty`

Expected: BUILD SUCCEEDED

**Step 4: Commit all button and wheel changes**

```bash
git add Shfl/Views/Components/ClickWheelView.swift Shfl/Views/Components/ClickWheelButton.swift Shfl/Views/Components/PlayPauseButton.swift
git commit -m "feat: add theme support to click wheel components"
```

---

## Task 6: Update NowPlayingInfo for Theme Support

**Files:**
- Modify: `Shfl/Views/Components/NowPlayingInfo.swift`

**Step 1: Update NowPlayingInfo to read theme from environment**

Replace `Shfl/Views/Components/NowPlayingInfo.swift`:

```swift
import SwiftUI

struct NowPlayingInfo: View {
    @Environment(\.shuffleTheme) private var theme

    let title: String
    let artist: String

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(theme.textColor)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            Text(artist)
                .font(.system(size: 16))
                .foregroundStyle(theme.secondaryTextColor)
                .lineLimit(1)
        }
    }
}

#Preview("Light Text") {
    NowPlayingInfo(title: "Song Title", artist: "Artist Name")
        .padding()
        .background(ShuffleTheme.pink.bodyGradient)
        .environment(\.shuffleTheme, .pink)
}

#Preview("Dark Text") {
    NowPlayingInfo(title: "Song Title", artist: "Artist Name")
        .padding()
        .background(ShuffleTheme.silver.bodyGradient)
        .environment(\.shuffleTheme, .silver)
}
```

**Step 2: Verify build succeeds**

Run: `xcodebuild build -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | xcpretty`

Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add Shfl/Views/Components/NowPlayingInfo.swift
git commit -m "feat: add theme support to NowPlayingInfo"
```

---

## Task 7: Update CapacityIndicator for Theme Support

**Files:**
- Modify: `Shfl/Views/Components/CapacityIndicator.swift`

**Step 1: Update CapacityIndicator to read theme from environment**

Replace `Shfl/Views/Components/CapacityIndicator.swift`:

```swift
import SwiftUI

struct CapacityIndicator: View {
    @Environment(\.shuffleTheme) private var theme

    let current: Int
    let maximum: Int

    private var pillBackground: Color {
        switch theme.textStyle {
        case .light: return .white.opacity(0.15)
        case .dark: return .black.opacity(0.1)
        }
    }

    var body: some View {
        Text("\(current)/\(maximum)")
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .foregroundStyle(theme.secondaryTextColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(pillBackground)
            )
    }
}

#Preview("Light Text") {
    VStack(spacing: 20) {
        CapacityIndicator(current: 0, maximum: 120)
        CapacityIndicator(current: 47, maximum: 120)
        CapacityIndicator(current: 120, maximum: 120)
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(ShuffleTheme.pink.bodyGradient)
    .environment(\.shuffleTheme, .pink)
}

#Preview("Dark Text") {
    VStack(spacing: 20) {
        CapacityIndicator(current: 47, maximum: 120)
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(ShuffleTheme.silver.bodyGradient)
    .environment(\.shuffleTheme, .silver)
}
```

**Step 2: Verify build succeeds**

Run: `xcodebuild build -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | xcpretty`

Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add Shfl/Views/Components/CapacityIndicator.swift
git commit -m "feat: add theme support to CapacityIndicator"
```

---

## Task 8: Update PlaybackProgressBar for Theme Support

**Files:**
- Modify: `Shfl/Views/Components/PlaybackProgressBar.swift`

**Step 1: Update PlaybackProgressBar to read theme from environment**

Replace `Shfl/Views/Components/PlaybackProgressBar.swift`:

```swift
import SwiftUI

struct PlaybackProgressBar: View {
    @Environment(\.shuffleTheme) private var theme

    let currentTime: TimeInterval
    let duration: TimeInterval

    private var progress: Double {
        guard duration > 0 else { return 0 }
        return min(currentTime / duration, 1.0)
    }

    private var trackBackground: Color {
        switch theme.textStyle {
        case .light: return .white.opacity(0.3)
        case .dark: return .black.opacity(0.2)
        }
    }

    private var trackFill: Color {
        switch theme.textStyle {
        case .light: return .white
        case .dark: return Color(white: 0.2)
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            // Progress track
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track
                    Capsule()
                        .fill(trackBackground)
                        .frame(height: 4)

                    // Filled track
                    Capsule()
                        .fill(trackFill)
                        .frame(width: geometry.size.width * progress, height: 4)
                }
            }
            .frame(height: 4)

            // Time labels
            HStack {
                Text(formatTime(currentTime))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(theme.secondaryTextColor)

                Spacer()

                Text(formatTime(duration))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(theme.secondaryTextColor)
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

#Preview("Light") {
    VStack(spacing: 40) {
        PlaybackProgressBar(currentTime: 78, duration: 242)
        PlaybackProgressBar(currentTime: 0, duration: 180)
    }
    .padding(32)
    .background(ShuffleTheme.blue.bodyGradient)
    .environment(\.shuffleTheme, .blue)
}

#Preview("Dark") {
    PlaybackProgressBar(currentTime: 78, duration: 242)
        .padding(32)
        .background(ShuffleTheme.silver.bodyGradient)
        .environment(\.shuffleTheme, .silver)
}
```

**Step 2: Verify build succeeds**

Run: `xcodebuild build -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | xcpretty`

Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add Shfl/Views/Components/PlaybackProgressBar.swift
git commit -m "feat: add theme support to PlaybackProgressBar"
```

---

## Task 9: Update PlayerView with Theme and Swipe Gesture

**Files:**
- Modify: `Shfl/Views/PlayerView.swift`

**Step 1: Add theme state and swipe gesture to PlayerView**

This is the largest change. Update `Shfl/Views/PlayerView.swift` to:
1. Add `@State private var currentThemeIndex: Int` initialized randomly
2. Add `@State private var dragOffset: CGFloat = 0`
3. Replace `backgroundGradient` with a ZStack showing current/adjacent themes
4. Add horizontal DragGesture with slide transition logic
5. Inject theme into environment for child views
6. Add haptic feedback on theme change and boundary bounce

Key implementation details:

```swift
// State
@State private var currentThemeIndex: Int = Int.random(in: 0..<ShuffleTheme.allThemes.count)
@State private var dragOffset: CGFloat = 0

// Computed
private var currentTheme: ShuffleTheme {
    ShuffleTheme.allThemes[currentThemeIndex]
}

// Swipe threshold
private let swipeThreshold: CGFloat = 100

// Background with gesture
private var themedBackground: some View {
    GeometryReader { geometry in
        HStack(spacing: 0) {
            // Previous theme (if exists)
            if currentThemeIndex > 0 {
                ShuffleTheme.allThemes[currentThemeIndex - 1].bodyGradient
                    .frame(width: geometry.size.width)
            }

            // Current theme
            currentTheme.bodyGradient
                .frame(width: geometry.size.width)

            // Next theme (if exists)
            if currentThemeIndex < ShuffleTheme.allThemes.count - 1 {
                ShuffleTheme.allThemes[currentThemeIndex + 1].bodyGradient
                    .frame(width: geometry.size.width)
            }
        }
        .offset(x: calculateBackgroundOffset(geometry: geometry))
    }
    .gesture(themeSwipeGesture)
    .ignoresSafeArea()
}

private func calculateBackgroundOffset(geometry: GeometryProxy) -> CGFloat {
    let baseOffset = currentThemeIndex > 0 ? -geometry.size.width : 0
    return baseOffset + dragOffset
}

private var themeSwipeGesture: some Gesture {
    DragGesture()
        .onChanged { value in
            let translation = value.translation.width
            // Add rubber-band resistance at edges
            if (currentThemeIndex == 0 && translation > 0) ||
               (currentThemeIndex == ShuffleTheme.allThemes.count - 1 && translation < 0) {
                dragOffset = translation * 0.3 // Resistance
            } else {
                dragOffset = translation
            }
        }
        .onEnded { value in
            let translation = value.translation.width
            let velocity = value.predictedEndTranslation.width

            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                if translation < -swipeThreshold || velocity < -500 {
                    // Swipe left - next theme
                    if currentThemeIndex < ShuffleTheme.allThemes.count - 1 {
                        currentThemeIndex += 1
                        HapticFeedback.light.trigger()
                    } else {
                        HapticFeedback.light.trigger() // Boundary bump
                    }
                } else if translation > swipeThreshold || velocity > 500 {
                    // Swipe right - previous theme
                    if currentThemeIndex > 0 {
                        currentThemeIndex -= 1
                        HapticFeedback.light.trigger()
                    } else {
                        HapticFeedback.light.trigger() // Boundary bump
                    }
                }
                dragOffset = 0
            }
        }
}
```

The full PlayerView update will replace `backgroundGradient` usage and wrap content with `.environment(\.shuffleTheme, currentTheme)`.

**Step 2: Verify build succeeds**

Run: `xcodebuild build -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | xcpretty`

Expected: BUILD SUCCEEDED

**Step 3: Run all tests to verify nothing broke**

Run: `xcodebuild test -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | xcpretty`

Expected: All tests PASS

**Step 4: Commit**

```bash
git add Shfl/Views/PlayerView.swift
git commit -m "feat: add swipeable theme switching to PlayerView"
```

---

## Task 10: Update PlayerView Text Elements for Theme

**Files:**
- Modify: `Shfl/Views/PlayerView.swift`

**Step 1: Update hardcoded white text colors in PlayerView**

In PlayerView, update:
- "View Library" button foreground color
- "No songs yet" / "Add some music" text colors
- Loading spinner tint

Change from `.white` / `.white.opacity(0.x)` to use `currentTheme.textColor` / `currentTheme.secondaryTextColor`.

**Step 2: Verify build succeeds**

Run: `xcodebuild build -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | xcpretty`

Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add Shfl/Views/PlayerView.swift
git commit -m "feat: update PlayerView text colors for theme support"
```

---

## Task 11: Final Integration Test

**Files:**
- None (manual testing)

**Step 1: Run full test suite**

Run: `xcodebuild test -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | xcpretty`

Expected: All tests PASS

**Step 2: Manual verification checklist**

- [ ] App launches with random theme color
- [ ] Swipe left changes to next theme with slide animation
- [ ] Swipe right changes to previous theme
- [ ] Silver theme has dark click wheel and dark text
- [ ] Blue/Green/Orange/Pink have light click wheel and white text
- [ ] Boundary swipe at Silver (first) rubber-bands back
- [ ] Boundary swipe at Pink (last) rubber-bands back
- [ ] Haptic feedback on successful theme change
- [ ] All text remains readable on all themes
- [ ] CapacityIndicator, NowPlayingInfo, progress bar adapt correctly

**Step 3: Commit any final fixes**

If any issues found, fix and commit with appropriate message.

---

## Summary

| Task | Description | Est. Complexity |
|------|-------------|-----------------|
| 1 | ShuffleTheme model + tests | Medium |
| 2 | ThemeEnvironment | Small |
| 3 | ClickWheelView theme support | Medium |
| 4 | ClickWheelButton theme support | Small |
| 5 | PlayPauseButton theme support | Small |
| 6 | NowPlayingInfo theme support | Small |
| 7 | CapacityIndicator theme support | Small |
| 8 | PlaybackProgressBar theme support | Small |
| 9 | PlayerView swipe gesture | Large |
| 10 | PlayerView text colors | Small |
| 11 | Integration testing | Medium |

Total: 11 tasks, mostly small isolated changes with one larger PlayerView update.
