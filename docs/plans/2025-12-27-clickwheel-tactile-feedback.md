# Click Wheel Tactile Feedback Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add physical tactile feedback to the click wheel - outer wheel tilts toward pressed buttons, center button depresses inward.

**Architecture:** Track press state in ClickWheelView via callbacks from child buttons. Apply 3D rotation transforms to the wheel and scale/shadow transforms to the center button. All parameters configurable via a central struct.

**Tech Stack:** SwiftUI, rotation3DEffect, DragGesture for press detection, spring animations

---

### Task 1: Create ClickWheelFeedback Configuration

**Files:**
- Create: `Shfl/Views/Components/ClickWheelFeedback.swift`

**Step 1: Create the configuration file**

```swift
import SwiftUI

/// Configuration for click wheel tactile feedback effects
struct ClickWheelFeedback {
    // MARK: - Wheel Tilt

    /// Rotation angle in degrees when a button is pressed (exaggerated = 10)
    static let tiltAngle: Double = 10

    /// Spring animation response time
    static let springResponse: Double = 0.3

    /// Spring animation damping (0.6 = slight bounce)
    static let springDampingFraction: Double = 0.6

    /// 3D perspective for rotation effect
    static let perspective: CGFloat = 0.3

    // MARK: - Center Button Depression

    /// Scale when pressed (0.92 = 8% smaller)
    static let centerPressScale: Double = 0.92

    /// Shadow radius when pressed
    static let centerPressedShadowRadius: CGFloat = 2

    /// Shadow Y offset when pressed
    static let centerPressedShadowY: CGFloat = 1

    /// Shadow radius when not pressed
    static let centerNormalShadowRadius: CGFloat = 8

    /// Shadow Y offset when not pressed
    static let centerNormalShadowY: CGFloat = 4
}

// MARK: - Press Position

/// Represents which button on the wheel is currently pressed
enum WheelPressPosition {
    case none
    case top      // Volume up
    case bottom   // Volume down
    case left     // Skip back
    case right    // Skip forward

    /// The 3D rotation axis for this press position
    var rotationAxis: (x: CGFloat, y: CGFloat, z: CGFloat) {
        switch self {
        case .none:
            return (0, 0, 0)
        case .top:
            return (1, 0, 0)      // Tilt forward (top sinks in)
        case .bottom:
            return (-1, 0, 0)     // Tilt backward (bottom sinks in)
        case .left:
            return (0, -1, 0)     // Tilt left
        case .right:
            return (0, 1, 0)      // Tilt right
        }
    }
}
```

**Step 2: Verify build succeeds**

Run: `xcodebuild -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | grep -E "(BUILD SUCCEEDED|BUILD FAILED|error:)"`

Expected: `** BUILD SUCCEEDED **`

**Step 3: Commit**

```bash
git add Shfl/Views/Components/ClickWheelFeedback.swift
git commit -m "feat: add ClickWheelFeedback configuration struct"
```

---

### Task 2: Add Press State Tracking to ClickWheelButton

**Files:**
- Modify: `Shfl/Views/Components/ClickWheelButton.swift`

**Step 1: Add onPressChanged callback and press state**

Add optional callback parameter and isPressed state to ClickWheelButton:

```swift
struct ClickWheelButton: View {
    let systemName: String
    let action: () -> Void
    var onPressChanged: ((Bool) -> Void)? = nil  // ADD THIS
    var wheelStyle: ShuffleTheme.WheelStyle = .light

    @State private var tapCount = 0
    @State private var isPressed = false  // ADD THIS
```

**Step 2: Replace Button with press-detecting gesture**

Replace the current Button implementation with a gesture-based approach that detects press start/end:

```swift
    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(iconColor)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle().size(width: 60, height: 60))
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isPressed {
                            isPressed = true
                            onPressChanged?(true)
                        }
                    }
                    .onEnded { _ in
                        isPressed = false
                        onPressChanged?(false)
                        tapCount += 1
                        action()
                    }
            )
            .sensoryFeedback(.impact(weight: .light), trigger: tapCount)
    }
```

**Step 3: Verify build succeeds**

Run: `xcodebuild -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | grep -E "(BUILD SUCCEEDED|BUILD FAILED|error:)"`

Expected: `** BUILD SUCCEEDED **`

**Step 4: Commit**

```bash
git add Shfl/Views/Components/ClickWheelButton.swift
git commit -m "feat: add press state tracking to ClickWheelButton"
```

---

### Task 3: Add Wheel Tilt to ClickWheelView

**Files:**
- Modify: `Shfl/Views/Components/ClickWheelView.swift`

**Step 1: Add press position state**

Add state variable at the top of the struct:

```swift
struct ClickWheelView: View {
    @Environment(\.shuffleTheme) private var theme

    let isPlaying: Bool
    let onPlayPause: () -> Void
    let onSkipForward: () -> Void
    let onSkipBack: () -> Void
    let onVolumeUp: () -> Void
    let onVolumeDown: () -> Void

    @State private var pressPosition: WheelPressPosition = .none  // ADD THIS

    private let wheelSize: CGFloat = 280
    private let centerButtonSize: CGFloat = 80
```

**Step 2: Update ClickWheelButton calls with onPressChanged**

Update all four button calls to include the press callback:

```swift
            VStack {
                ClickWheelButton(
                    systemName: "plus",
                    action: onVolumeUp,
                    onPressChanged: { isPressed in pressPosition = isPressed ? .top : .none },
                    wheelStyle: theme.wheelStyle
                )
                Spacer()
            }
            .frame(height: wheelSize - 40)

            VStack {
                Spacer()
                ClickWheelButton(
                    systemName: "minus",
                    action: onVolumeDown,
                    onPressChanged: { isPressed in pressPosition = isPressed ? .bottom : .none },
                    wheelStyle: theme.wheelStyle
                )
            }
            .frame(height: wheelSize - 40)

            HStack {
                ClickWheelButton(
                    systemName: "backward.end.fill",
                    action: onSkipBack,
                    onPressChanged: { isPressed in pressPosition = isPressed ? .left : .none },
                    wheelStyle: theme.wheelStyle
                )
                Spacer()
            }
            .frame(width: wheelSize - 40)

            HStack {
                Spacer()
                ClickWheelButton(
                    systemName: "forward.end.fill",
                    action: onSkipForward,
                    onPressChanged: { isPressed in pressPosition = isPressed ? .right : .none },
                    wheelStyle: theme.wheelStyle
                )
            }
            .frame(width: wheelSize - 40)
```

**Step 3: Add 3D rotation effect to the ZStack**

Wrap the existing ZStack content and add the rotation modifier:

```swift
    var body: some View {
        ZStack {
            // Outer wheel background
            Circle()
                .fill(wheelGradient)
                .frame(width: wheelSize, height: wheelSize)
                .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 6)

            // Control buttons positioned around the wheel
            VStack {
                ClickWheelButton(
                    systemName: "plus",
                    action: onVolumeUp,
                    onPressChanged: { isPressed in pressPosition = isPressed ? .top : .none },
                    wheelStyle: theme.wheelStyle
                )
                Spacer()
            }
            .frame(height: wheelSize - 40)

            VStack {
                Spacer()
                ClickWheelButton(
                    systemName: "minus",
                    action: onVolumeDown,
                    onPressChanged: { isPressed in pressPosition = isPressed ? .bottom : .none },
                    wheelStyle: theme.wheelStyle
                )
            }
            .frame(height: wheelSize - 40)

            HStack {
                ClickWheelButton(
                    systemName: "backward.end.fill",
                    action: onSkipBack,
                    onPressChanged: { isPressed in pressPosition = isPressed ? .left : .none },
                    wheelStyle: theme.wheelStyle
                )
                Spacer()
            }
            .frame(width: wheelSize - 40)

            HStack {
                Spacer()
                ClickWheelButton(
                    systemName: "forward.end.fill",
                    action: onSkipForward,
                    onPressChanged: { isPressed in pressPosition = isPressed ? .right : .none },
                    wheelStyle: theme.wheelStyle
                )
            }
            .frame(width: wheelSize - 40)

            // Center play/pause button
            PlayPauseButton(isPlaying: isPlaying, action: onPlayPause, wheelStyle: theme.wheelStyle)
        }
        .compositingGroup()
        .rotation3DEffect(
            .degrees(pressPosition != .none ? ClickWheelFeedback.tiltAngle : 0),
            axis: pressPosition.rotationAxis,
            perspective: ClickWheelFeedback.perspective
        )
        .animation(
            .spring(response: ClickWheelFeedback.springResponse, dampingFraction: ClickWheelFeedback.springDampingFraction),
            value: pressPosition
        )
    }
```

**Step 4: Verify build succeeds**

Run: `xcodebuild -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | grep -E "(BUILD SUCCEEDED|BUILD FAILED|error:)"`

Expected: `** BUILD SUCCEEDED **`

**Step 5: Commit**

```bash
git add Shfl/Views/Components/ClickWheelView.swift
git commit -m "feat: add 3D tilt effect to click wheel on button press"
```

---

### Task 4: Add Depression Effect to PlayPauseButton

**Files:**
- Modify: `Shfl/Views/Components/PlayPauseButton.swift`

**Step 1: Add isPressed state**

Add state variable at the top of the struct:

```swift
struct PlayPauseButton: View {
    let isPlaying: Bool
    let action: () -> Void
    var wheelStyle: ShuffleTheme.WheelStyle = .light

    @State private var isPressed = false  // ADD THIS
```

**Step 2: Update the body with press gesture and visual effects**

Replace the body implementation to add press detection and visual feedback:

```swift
    var body: some View {
        ZStack {
            Circle()
                .fill(buttonBackgroundColor)
                .frame(width: 80, height: 80)
                .shadow(
                    color: .black.opacity(0.1),
                    radius: isPressed ? ClickWheelFeedback.centerPressedShadowRadius : ClickWheelFeedback.centerNormalShadowRadius,
                    x: 0,
                    y: isPressed ? ClickWheelFeedback.centerPressedShadowY : ClickWheelFeedback.centerNormalShadowY
                )

            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(iconColor)
                .offset(x: isPlaying ? 0 : 2)
        }
        .scaleEffect(isPressed ? ClickWheelFeedback.centerPressScale : 1.0)
        .animation(.spring(response: ClickWheelFeedback.springResponse, dampingFraction: ClickWheelFeedback.springDampingFraction), value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed {
                        isPressed = true
                    }
                }
                .onEnded { _ in
                    isPressed = false
                    action()
                }
        )
        .sensoryFeedback(.impact(weight: .medium), trigger: isPlaying)
    }
```

**Step 3: Verify build succeeds**

Run: `xcodebuild -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | grep -E "(BUILD SUCCEEDED|BUILD FAILED|error:)"`

Expected: `** BUILD SUCCEEDED **`

**Step 4: Commit**

```bash
git add Shfl/Views/Components/PlayPauseButton.swift
git commit -m "feat: add depression effect to play/pause button"
```

---

### Task 5: Run Full Test Suite and Verify

**Step 1: Run all tests**

Run: `xcodebuild test -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "(Test Suite|passed|failed|BUILD)"`

Expected: All tests pass, BUILD SUCCEEDED

**Step 2: Manual verification in preview**

Open Xcode and check the SwiftUI previews for:
- `ClickWheelView` - verify tilt effect on button press
- `PlayPauseButton` - verify depression effect on press
- `ClickWheelButton` - verify button still triggers actions

**Step 3: Final commit if any adjustments needed**

```bash
git status
# If clean, skip. If changes needed, commit them.
```

---

## Summary

| Task | Description | Files |
|------|-------------|-------|
| 1 | Create configuration struct | ClickWheelFeedback.swift (new) |
| 2 | Add press tracking to buttons | ClickWheelButton.swift |
| 3 | Add wheel tilt effect | ClickWheelView.swift |
| 4 | Add center button depression | PlayPauseButton.swift |
| 5 | Verify tests and manual testing | - |
