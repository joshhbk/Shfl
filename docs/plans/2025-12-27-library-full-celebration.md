# Library Full Celebration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a breathing glow animation + haptic when the library fills to 120 songs, inspired by the MacBook sleep indicator.

**Architecture:** Self-contained within `CapacityProgressBar`. Track previous count to detect 119→120 transition. Trigger haptic immediately, then animate a white glow behind the progress bar for 2 breath cycles (~4 seconds). Respect Reduce Motion accessibility setting.

**Tech Stack:** SwiftUI animations, UIImpactFeedbackGenerator, @Environment(\.accessibilityReduceMotion)

---

## Task 1: Add Celebration Detection Logic

**Files:**
- Modify: `Shfl/Views/Components/CapacityProgressBar.swift:42-51`
- Test: `ShflTests/Views/CapacityProgressBarTests.swift`

**Step 1: Write the failing test**

Add to `ShflTests/Views/CapacityProgressBarTests.swift`:

```swift
@Test("Celebration triggers only on transition to full")
func testShouldCelebrateOnTransitionToFull() {
    // Only celebrates when transitioning from not-full to full
    #expect(CapacityProgressBar.shouldCelebrate(previous: 119, current: 120, maximum: 120))
    #expect(!CapacityProgressBar.shouldCelebrate(previous: 120, current: 120, maximum: 120))
    #expect(!CapacityProgressBar.shouldCelebrate(previous: 118, current: 119, maximum: 120))
    #expect(!CapacityProgressBar.shouldCelebrate(previous: 0, current: 0, maximum: 120))
}

@Test("Celebration does not trigger when already at capacity")
func testNoCelebrationWhenAlreadyFull() {
    #expect(!CapacityProgressBar.shouldCelebrate(previous: 120, current: 120, maximum: 120))
}

@Test("Celebration triggers when jumping to full")
func testCelebrationOnJumpToFull() {
    // e.g., autofill adding many songs at once
    #expect(CapacityProgressBar.shouldCelebrate(previous: 50, current: 120, maximum: 120))
    #expect(CapacityProgressBar.shouldCelebrate(previous: 0, current: 120, maximum: 120))
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -project Shfl.xcodeproj -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:ShflTests/CapacityProgressBarTests 2>&1 | grep -E "(passed|failed|error:)"`

Expected: FAIL with "shouldCelebrate" not found

**Step 3: Write minimal implementation**

Add to `Shfl/Views/Components/CapacityProgressBar.swift` in the static helpers section:

```swift
static func shouldCelebrate(previous: Int, current: Int, maximum: Int) -> Bool {
    let wasNotFull = previous < maximum
    let isNowFull = current >= maximum
    return wasNotFull && isNowFull
}
```

**Step 4: Run test to verify it passes**

Run: `xcodebuild test -project Shfl.xcodeproj -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:ShflTests/CapacityProgressBarTests 2>&1 | grep -E "(passed|failed|error:)"`

Expected: All tests PASS

**Step 5: Commit**

```bash
git add Shfl/Views/Components/CapacityProgressBar.swift ShflTests/Views/CapacityProgressBarTests.swift
git commit -m "feat: add shouldCelebrate detection logic"
```

---

## Task 2: Add BreathingGlow View Component

**Files:**
- Modify: `Shfl/Views/Components/CapacityProgressBar.swift`

**Step 1: Add the BreathingGlow private view**

Add before the `CapacityProgressBar` struct:

```swift
private struct BreathingGlow: View {
    @State private var isBreathing = false
    let onComplete: () -> Void

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.white)
            .blur(radius: isBreathing ? 12 : 8)
            .opacity(isBreathing ? 0.4 : 0.0)
            .scaleEffect(isBreathing ? 1.05 : 1.0)
            .animation(
                .easeInOut(duration: 1.0).repeatCount(4, autoreverses: true),
                value: isBreathing
            )
            .onAppear {
                isBreathing = true
                // 4 half-cycles = 2 full breaths = 4 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                    onComplete()
                }
            }
    }
}
```

**Step 2: Run build to verify it compiles**

Run: `xcodebuild build -project Shfl.xcodeproj -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "(error:|BUILD)"`

Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add Shfl/Views/Components/CapacityProgressBar.swift
git commit -m "feat: add BreathingGlow private view component"
```

---

## Task 3: Wire Up Celebration State

**Files:**
- Modify: `Shfl/Views/Components/CapacityProgressBar.swift`

**Step 1: Add state tracking to CapacityProgressBar**

Update `CapacityProgressBar` struct to add state:

```swift
struct CapacityProgressBar: View {
    let current: Int
    let maximum: Int

    @State private var previousCount: Int?
    @State private var isShowingCelebration = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
```

**Step 2: Add onChange to detect transitions**

Add after the `.background(Color(.systemGroupedBackground))` line:

```swift
.onChange(of: current) { oldValue, newValue in
    if Self.shouldCelebrate(previous: oldValue, current: newValue, maximum: maximum) {
        triggerCelebration()
    }
}
```

**Step 3: Add triggerCelebration method**

Add as a private method in the struct:

```swift
private func triggerCelebration() {
    HapticFeedback.medium.trigger()
    if !reduceMotion {
        isShowingCelebration = true
    }
}
```

**Step 4: Run build to verify it compiles**

Run: `xcodebuild build -project Shfl.xcodeproj -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "(error:|BUILD)"`

Expected: BUILD SUCCEEDED

**Step 5: Commit**

```bash
git add Shfl/Views/Components/CapacityProgressBar.swift
git commit -m "feat: add celebration state tracking and haptic trigger"
```

---

## Task 4: Integrate BreathingGlow into Progress Bar

**Files:**
- Modify: `Shfl/Views/Components/CapacityProgressBar.swift`

**Step 1: Wrap the progress bar ZStack with the glow**

Replace the GeometryReader content with:

```swift
GeometryReader { geometry in
    ZStack(alignment: .leading) {
        // Glow layer (behind everything)
        if isShowingCelebration {
            BreathingGlow {
                isShowingCelebration = false
            }
            .frame(width: geometry.size.width, height: 6)
        }

        // Track
        RoundedRectangle(cornerRadius: 2)
            .fill(Color.gray.opacity(0.2))

        // Fill
        RoundedRectangle(cornerRadius: 2)
            .fill(isFull ? Color.green : Color.blue)
            .frame(width: geometry.size.width * progress)
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: progress)
    }
}
```

**Step 2: Run all tests to verify nothing broke**

Run: `xcodebuild test -project Shfl.xcodeproj -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:ShflTests 2>&1 | grep -E "(passed|failed|Executed)"`

Expected: All tests PASS

**Step 3: Commit**

```bash
git add Shfl/Views/Components/CapacityProgressBar.swift
git commit -m "feat: integrate BreathingGlow into progress bar"
```

---

## Task 5: Add Preview for Celebration State

**Files:**
- Modify: `Shfl/Views/Components/CapacityProgressBar.swift`

**Step 1: Update Preview to include celebration demo**

Replace the existing `#Preview` with:

```swift
#Preview("States") {
    VStack(spacing: 20) {
        CapacityProgressBar(current: 0, maximum: 120)
        CapacityProgressBar(current: 42, maximum: 120)
        CapacityProgressBar(current: 100, maximum: 120)
        CapacityProgressBar(current: 120, maximum: 120)
    }
    .padding()
}

#Preview("Celebration") {
    struct CelebrationDemo: View {
        @State private var count = 119

        var body: some View {
            VStack(spacing: 20) {
                CapacityProgressBar(current: count, maximum: 120)

                Button("Fill Library") {
                    count = 120
                }
                .buttonStyle(.borderedProminent)

                Button("Reset") {
                    count = 119
                }
            }
            .padding()
        }
    }
    return CelebrationDemo()
}
```

**Step 2: Run build to verify previews compile**

Run: `xcodebuild build -project Shfl.xcodeproj -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "(error:|BUILD)"`

Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add Shfl/Views/Components/CapacityProgressBar.swift
git commit -m "feat: add celebration preview for manual testing"
```

---

## Task 6: Run Full Test Suite and Final Commit

**Step 1: Run all tests**

Run: `xcodebuild test -project Shfl.xcodeproj -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "(passed|failed|Executed)"`

Expected: All tests PASS

**Step 2: Manual verification in Preview**

Open Xcode, navigate to `CapacityProgressBar.swift`, and use the "Celebration" preview to verify:
- Haptic fires on tap
- White glow appears behind the green bar
- Glow breathes twice over ~4 seconds
- Glow fades out cleanly

**Step 3: Final commit if any adjustments made**

```bash
git add -A
git commit -m "feat: library full celebration complete"
```

---

## Summary

| Task | Description | Commit |
|------|-------------|--------|
| 1 | Detection logic with TDD | `feat: add shouldCelebrate detection logic` |
| 2 | BreathingGlow component | `feat: add BreathingGlow private view component` |
| 3 | State tracking + haptic | `feat: add celebration state tracking and haptic trigger` |
| 4 | Integration | `feat: integrate BreathingGlow into progress bar` |
| 5 | Preview for testing | `feat: add celebration preview for manual testing` |
| 6 | Full verification | `feat: library full celebration complete` |

## Testing Notes

- **Haptic:** Must test on physical device (simulator doesn't support haptics)
- **Reduce Motion:** Toggle in Settings > Accessibility > Motion to verify glow is skipped
- **Timing:** Watch the preview - should be exactly 2 breath cycles (~4 seconds)
