# Brushed Metal Texture Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a concentric ring brushed metal texture to PlayerView background that recreates the iPod Shuffle 4th gen's machined aluminum finish with motion-reactive highlights.

**Architecture:** Canvas-based concentric ring drawing overlaid with a radial highlight gradient. MotionManager service provides device tilt data via CoreMotion. Configuration flows through ShuffleTheme to allow per-theme tuning.

**Tech Stack:** SwiftUI Canvas, CoreMotion CMMotionManager, Swift Testing

---

## Task 1: Create BrushedMetalBackground with Static Rings

**Files:**
- Create: `Shfl/Views/Components/BrushedMetalBackground.swift`
- Create: `ShflTests/Views/BrushedMetalBackgroundTests.swift`

**Step 1: Write the failing test**

Create `ShflTests/Views/BrushedMetalBackgroundTests.swift`:

```swift
import SwiftUI
import Testing
@testable import Shfl

@Suite("BrushedMetalBackground Tests")
struct BrushedMetalBackgroundTests {

    @Test("Ring count calculation returns expected rings for size")
    func ringCountForSize() {
        // 200pt radius with 2pt spacing = 100 rings
        let count = BrushedMetalBackground.ringCount(for: 200, spacing: 2)
        #expect(count == 100)
    }

    @Test("Ring opacity alternates between light and dark")
    func ringOpacityAlternates() {
        let opacity0 = BrushedMetalBackground.ringOpacity(at: 0, intensity: 1.0)
        let opacity1 = BrushedMetalBackground.ringOpacity(at: 1, intensity: 1.0)
        #expect(opacity0 != opacity1, "Adjacent rings should have different opacity")
    }

    @Test("Zero intensity returns zero opacity")
    func zeroIntensityReturnsZero() {
        let opacity = BrushedMetalBackground.ringOpacity(at: 0, intensity: 0.0)
        #expect(opacity == 0.0)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -project Shfl.xcodeproj -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:ShflTests/BrushedMetalBackgroundTests -quiet 2>&1 | grep -E "(passed|failed|error)"`

Expected: Build error - `BrushedMetalBackground` not found

**Step 3: Write minimal implementation**

Create `Shfl/Views/Components/BrushedMetalBackground.swift`:

```swift
import SwiftUI

struct BrushedMetalBackground: View {
    let baseColor: Color
    let intensity: CGFloat

    init(baseColor: Color, intensity: CGFloat = 0.5) {
        self.baseColor = baseColor
        self.intensity = intensity
    }

    var body: some View {
        GeometryReader { geometry in
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            let maxRadius = max(geometry.size.width, geometry.size.height)

            Canvas { context, size in
                let ringSpacing: CGFloat = 2.0
                let rings = Self.ringCount(for: maxRadius, spacing: ringSpacing)

                for i in 0..<rings {
                    let radius = CGFloat(i) * ringSpacing
                    let opacity = Self.ringOpacity(at: i, intensity: intensity)

                    let ringColor = Color.white.opacity(opacity)

                    let path = Path { p in
                        p.addArc(
                            center: center,
                            radius: radius,
                            startAngle: .zero,
                            endAngle: .degrees(360),
                            clockwise: false
                        )
                    }

                    context.stroke(path, with: .color(ringColor), lineWidth: 1)
                }
            }
        }
        .background(baseColor)
    }

    // MARK: - Calculations (static for testability)

    static func ringCount(for radius: CGFloat, spacing: CGFloat) -> Int {
        Int(radius / spacing)
    }

    static func ringOpacity(at index: Int, intensity: CGFloat) -> CGFloat {
        guard intensity > 0 else { return 0 }

        // Alternate between lighter and darker rings
        let baseOpacity: CGFloat = index.isMultiple(of: 2) ? 0.08 : 0.04
        return baseOpacity * intensity
    }
}

#Preview {
    BrushedMetalBackground(baseColor: Color(red: 0.75, green: 0.75, blue: 0.75))
}
```

**Step 4: Run test to verify it passes**

Run: `xcodebuild test -project Shfl.xcodeproj -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:ShflTests/BrushedMetalBackgroundTests -quiet 2>&1 | grep -E "(passed|failed)"`

Expected: All 3 tests pass

**Step 5: Commit**

```bash
git add Shfl/Views/Components/BrushedMetalBackground.swift ShflTests/Views/BrushedMetalBackgroundTests.swift
git commit -m "feat: add BrushedMetalBackground with static concentric rings"
```

---

## Task 2: Integrate BrushedMetalBackground into PlayerView

**Files:**
- Modify: `Shfl/Views/PlayerView.swift:39-42`

**Step 1: Replace gradient background with BrushedMetalBackground**

In `PlayerView.swift`, change the background from:

```swift
// Background - first in ZStack = behind
currentTheme.bodyGradient
```

To:

```swift
// Background - first in ZStack = behind
BrushedMetalBackground(
    baseColor: currentTheme.bodyGradientTop
)
```

**Step 2: Build and run preview**

Run: `xcodebuild build -project Shfl.xcodeproj -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`

Expected: Build succeeds

**Step 3: Verify visually in preview**

Open Xcode previews or run the app. The player background should now show subtle concentric rings over the theme color.

**Step 4: Commit**

```bash
git add Shfl/Views/PlayerView.swift
git commit -m "feat: use BrushedMetalBackground in PlayerView"
```

---

## Task 3: Create MotionManager Service

**Files:**
- Create: `Shfl/Services/MotionManager.swift`
- Create: `ShflTests/Services/MotionManagerTests.swift`

**Step 1: Write the failing test**

Create `ShflTests/Services/MotionManagerTests.swift`:

```swift
import Testing
@testable import Shfl

@Suite("MotionManager Tests")
struct MotionManagerTests {

    @Test("Initial pitch and roll are zero")
    func initialValuesAreZero() {
        let manager = MotionManager()
        #expect(manager.pitch == 0)
        #expect(manager.roll == 0)
    }

    @Test("Highlight offset calculation maps tilt to offset")
    func highlightOffsetCalculation() {
        // With sensitivity 1.0, max tilt should give max offset
        let offset = MotionManager.highlightOffset(
            pitch: 0.5,  // ~28 degrees
            roll: 0.3,
            sensitivity: 1.0,
            maxOffset: 50
        )
        #expect(offset.x != 0 || offset.y != 0, "Should produce non-zero offset")
    }

    @Test("Zero sensitivity produces zero offset")
    func zeroSensitivityProducesZeroOffset() {
        let offset = MotionManager.highlightOffset(
            pitch: 0.5,
            roll: 0.5,
            sensitivity: 0,
            maxOffset: 50
        )
        #expect(offset.x == 0 && offset.y == 0)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -project Shfl.xcodeproj -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:ShflTests/MotionManagerTests -quiet 2>&1 | grep -E "(passed|failed|error)"`

Expected: Build error - `MotionManager` not found

**Step 3: Write minimal implementation**

Create `Shfl/Services/MotionManager.swift`:

```swift
import CoreMotion
import SwiftUI

@Observable
final class MotionManager {
    private(set) var pitch: Double = 0
    private(set) var roll: Double = 0
    private(set) var isAvailable: Bool = false

    private let motionManager = CMMotionManager()
    private let updateInterval: TimeInterval = 1.0 / 30.0  // 30Hz

    init() {
        isAvailable = motionManager.isDeviceMotionAvailable
    }

    func start() {
        guard motionManager.isDeviceMotionAvailable else { return }

        motionManager.deviceMotionUpdateInterval = updateInterval
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let motion = motion else { return }
            self?.pitch = motion.attitude.pitch
            self?.roll = motion.attitude.roll
        }
    }

    func stop() {
        motionManager.stopDeviceMotionUpdates()
    }

    // MARK: - Calculations (static for testability)

    static func highlightOffset(
        pitch: Double,
        roll: Double,
        sensitivity: CGFloat,
        maxOffset: CGFloat
    ) -> CGPoint {
        guard sensitivity > 0 else { return .zero }

        // Map pitch/roll (-π to π) to offset (-maxOffset to maxOffset)
        // Clamp to reasonable range (about ±45 degrees of tilt)
        let clampedPitch = max(-0.8, min(0.8, pitch))
        let clampedRoll = max(-0.8, min(0.8, roll))

        let x = CGFloat(clampedRoll) * maxOffset * sensitivity / 0.8
        let y = CGFloat(clampedPitch) * maxOffset * sensitivity / 0.8

        return CGPoint(x: x, y: -y)  // Invert Y so tilting forward moves highlight up
    }
}
```

**Step 4: Run test to verify it passes**

Run: `xcodebuild test -project Shfl.xcodeproj -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:ShflTests/MotionManagerTests -quiet 2>&1 | grep -E "(passed|failed)"`

Expected: All 3 tests pass

**Step 5: Commit**

```bash
git add Shfl/Services/MotionManager.swift ShflTests/Services/MotionManagerTests.swift
git commit -m "feat: add MotionManager for device tilt tracking"
```

---

## Task 4: Add Environment Support for MotionManager

**Files:**
- Modify: `Shfl/Theme/ThemeEnvironment.swift`
- Modify: `Shfl/ShuffledApp.swift`

**Step 1: Add MotionManager environment key**

In `ThemeEnvironment.swift`, add after the existing code:

```swift
private struct MotionManagerKey: EnvironmentKey {
    static let defaultValue: MotionManager? = nil
}

extension EnvironmentValues {
    var motionManager: MotionManager? {
        get { self[MotionManagerKey.self] }
        set { self[MotionManagerKey.self] = newValue }
    }
}
```

**Step 2: Read ShuffledApp.swift to find injection point**

Read the file to understand structure before modifying.

**Step 3: Add MotionManager to app environment**

In `ShuffledApp.swift`, add a `@State` property for the manager and inject it via environment.

**Step 4: Build to verify**

Run: `xcodebuild build -project Shfl.xcodeproj -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`

Expected: Build succeeds

**Step 5: Commit**

```bash
git add Shfl/Theme/ThemeEnvironment.swift Shfl/ShuffledApp.swift
git commit -m "feat: add MotionManager to environment"
```

---

## Task 5: Add Dynamic Highlight to BrushedMetalBackground

**Files:**
- Modify: `Shfl/Views/Components/BrushedMetalBackground.swift`
- Modify: `ShflTests/Views/BrushedMetalBackgroundTests.swift`

**Step 1: Update test for highlight gradient**

Add to `BrushedMetalBackgroundTests.swift`:

```swift
@Test("Highlight gradient center offset responds to input")
func highlightGradientOffset() {
    let offset = CGPoint(x: 20, y: -10)
    let center = CGPoint(x: 200, y: 300)
    let result = BrushedMetalBackground.highlightCenter(base: center, offset: offset)
    #expect(result.x == 220)
    #expect(result.y == 290)
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -project Shfl.xcodeproj -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:ShflTests/BrushedMetalBackgroundTests/highlightGradientOffset -quiet 2>&1 | grep -E "(passed|failed|error)"`

Expected: Compile error - `highlightCenter` not found

**Step 3: Add highlight gradient overlay**

Update `BrushedMetalBackground.swift`:

1. Add parameters: `highlightOffset: CGPoint = .zero`, `motionEnabled: Bool = true`
2. Add static function `highlightCenter`
3. Add RadialGradient overlay that shifts based on `highlightOffset`

```swift
struct BrushedMetalBackground: View {
    let baseColor: Color
    let intensity: CGFloat
    let highlightOffset: CGPoint
    let motionEnabled: Bool

    init(
        baseColor: Color,
        intensity: CGFloat = 0.5,
        highlightOffset: CGPoint = .zero,
        motionEnabled: Bool = true
    ) {
        self.baseColor = baseColor
        self.intensity = intensity
        self.highlightOffset = motionEnabled ? highlightOffset : .zero
        self.motionEnabled = motionEnabled
    }

    var body: some View {
        GeometryReader { geometry in
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            let maxRadius = max(geometry.size.width, geometry.size.height)
            let highlightCenter = Self.highlightCenter(base: center, offset: highlightOffset)

            ZStack {
                // Base color
                baseColor

                // Concentric rings
                Canvas { context, size in
                    let ringSpacing: CGFloat = 2.0
                    let rings = Self.ringCount(for: maxRadius, spacing: ringSpacing)

                    for i in 0..<rings {
                        let radius = CGFloat(i) * ringSpacing
                        let opacity = Self.ringOpacity(at: i, intensity: intensity)
                        let ringColor = Color.white.opacity(opacity)

                        let path = Path { p in
                            p.addArc(
                                center: center,
                                radius: radius,
                                startAngle: .zero,
                                endAngle: .degrees(360),
                                clockwise: false
                            )
                        }

                        context.stroke(path, with: .color(ringColor), lineWidth: 1)
                    }
                }

                // Highlight gradient
                RadialGradient(
                    colors: [
                        Color.white.opacity(0.15 * intensity),
                        Color.white.opacity(0.05 * intensity),
                        Color.clear
                    ],
                    center: UnitPoint(
                        x: highlightCenter.x / geometry.size.width,
                        y: highlightCenter.y / geometry.size.height
                    ),
                    startRadius: 0,
                    endRadius: maxRadius * 0.6
                )
            }
        }
    }

    // MARK: - Calculations

    static func ringCount(for radius: CGFloat, spacing: CGFloat) -> Int {
        Int(radius / spacing)
    }

    static func ringOpacity(at index: Int, intensity: CGFloat) -> CGFloat {
        guard intensity > 0 else { return 0 }
        let baseOpacity: CGFloat = index.isMultiple(of: 2) ? 0.08 : 0.04
        return baseOpacity * intensity
    }

    static func highlightCenter(base: CGPoint, offset: CGPoint) -> CGPoint {
        CGPoint(x: base.x + offset.x, y: base.y + offset.y)
    }
}
```

**Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project Shfl.xcodeproj -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:ShflTests/BrushedMetalBackgroundTests -quiet 2>&1 | grep -E "(passed|failed)"`

Expected: All 4 tests pass

**Step 5: Commit**

```bash
git add Shfl/Views/Components/BrushedMetalBackground.swift ShflTests/Views/BrushedMetalBackgroundTests.swift
git commit -m "feat: add motion-reactive highlight to BrushedMetalBackground"
```

---

## Task 6: Wire MotionManager to PlayerView

**Files:**
- Modify: `Shfl/Views/PlayerView.swift`

**Step 1: Add environment access and state**

At the top of PlayerView, add:

```swift
@Environment(\.motionManager) private var motionManager
@State private var highlightOffset: CGPoint = .zero
```

**Step 2: Update BrushedMetalBackground usage**

Change the background to:

```swift
BrushedMetalBackground(
    baseColor: currentTheme.bodyGradientTop,
    highlightOffset: highlightOffset
)
```

**Step 3: Add motion observation**

In `.onAppear`, start motion updates. In `.onDisappear`, stop them.
Add an `.onChange` or use a computed binding to update `highlightOffset` from the motion manager.

For simplicity, use a timer or `withObservationTracking` pattern:

```swift
.onAppear {
    startProgressTimer()
    motionManager?.start()
}
.onDisappear {
    stopProgressTimer()
    motionManager?.stop()
}
.onChange(of: motionManager?.pitch) { _, _ in
    updateHighlightOffset()
}
.onChange(of: motionManager?.roll) { _, _ in
    updateHighlightOffset()
}
```

Add helper:

```swift
private func updateHighlightOffset() {
    guard let manager = motionManager else { return }
    highlightOffset = MotionManager.highlightOffset(
        pitch: manager.pitch,
        roll: manager.roll,
        sensitivity: 0.5,  // Will move to theme later
        maxOffset: 50
    )
}
```

**Step 4: Build and test on device**

Run on a physical device to verify motion works. Simulator won't show motion.

**Step 5: Commit**

```bash
git add Shfl/Views/PlayerView.swift
git commit -m "feat: wire MotionManager to PlayerView for dynamic highlight"
```

---

## Task 7: Add Configuration to ShuffleTheme

**Files:**
- Modify: `Shfl/Theme/ShuffleTheme.swift`
- Modify: `ShflTests/Theme/ShuffleThemeTests.swift`

**Step 1: Write the failing test**

Add to `ShuffleThemeTests.swift`:

```swift
@Test("All themes have brushed metal configuration")
func allThemesHaveBrushedMetalConfig() {
    for theme in ShuffleTheme.allThemes {
        #expect(theme.brushedMetalIntensity >= 0 && theme.brushedMetalIntensity <= 1)
        #expect(theme.motionSensitivity >= 0 && theme.motionSensitivity <= 1)
    }
}
```

**Step 2: Run test to verify it fails**

Expected: Compile error - properties not found

**Step 3: Add properties to ShuffleTheme**

In `ShuffleTheme.swift`, add to the struct:

```swift
let brushedMetalIntensity: CGFloat
let motionEnabled: Bool
let motionSensitivity: CGFloat
```

Update all theme definitions with default values:

```swift
brushedMetalIntensity: 0.5,
motionEnabled: true,
motionSensitivity: 0.5
```

**Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project Shfl.xcodeproj -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:ShflTests/ShuffleThemeTests -quiet 2>&1 | grep -E "(passed|failed)"`

Expected: All tests pass

**Step 5: Commit**

```bash
git add Shfl/Theme/ShuffleTheme.swift ShflTests/Theme/ShuffleThemeTests.swift
git commit -m "feat: add brushed metal configuration to ShuffleTheme"
```

---

## Task 8: Wire Theme Configuration to BrushedMetalBackground

**Files:**
- Modify: `Shfl/Views/PlayerView.swift`

**Step 1: Update BrushedMetalBackground to use theme config**

Change:

```swift
BrushedMetalBackground(
    baseColor: currentTheme.bodyGradientTop,
    highlightOffset: highlightOffset
)
```

To:

```swift
BrushedMetalBackground(
    baseColor: currentTheme.bodyGradientTop,
    intensity: currentTheme.brushedMetalIntensity,
    highlightOffset: highlightOffset,
    motionEnabled: currentTheme.motionEnabled
)
```

**Step 2: Update motion sensitivity in offset calculation**

Change `updateHighlightOffset()` to use theme sensitivity:

```swift
private func updateHighlightOffset() {
    guard let manager = motionManager else { return }
    highlightOffset = MotionManager.highlightOffset(
        pitch: manager.pitch,
        roll: manager.roll,
        sensitivity: currentTheme.motionSensitivity,
        maxOffset: 50
    )
}
```

**Step 3: Build and verify**

Run: `xcodebuild build -project Shfl.xcodeproj -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`

**Step 4: Commit**

```bash
git add Shfl/Views/PlayerView.swift
git commit -m "feat: wire theme configuration to brushed metal background"
```

---

## Task 9: Run Full Test Suite and Final Polish

**Files:**
- All modified files

**Step 1: Run full test suite**

Run: `xcodebuild test -project Shfl.xcodeproj -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet 2>&1 | tail -10`

Expected: All tests pass

**Step 2: Visual review on device**

- Run on physical device
- Swipe through all themes
- Verify rings are visible but subtle
- Verify highlight moves with tilt
- Verify no performance issues

**Step 3: Adjust intensity values if needed**

If rings are too prominent or too subtle, adjust `brushedMetalIntensity` defaults in theme definitions.

**Step 4: Final commit**

```bash
git add -A
git commit -m "polish: finalize brushed metal texture"
```

---

## Summary

| Task | Description | Files |
|------|-------------|-------|
| 1 | BrushedMetalBackground with static rings | New component + tests |
| 2 | Integrate into PlayerView | PlayerView.swift |
| 3 | MotionManager service | New service + tests |
| 4 | Environment support | ThemeEnvironment, App |
| 5 | Dynamic highlight | Component update |
| 6 | Wire motion to PlayerView | PlayerView.swift |
| 7 | Theme configuration | ShuffleTheme + tests |
| 8 | Wire theme to component | PlayerView.swift |
| 9 | Final testing and polish | All files |
