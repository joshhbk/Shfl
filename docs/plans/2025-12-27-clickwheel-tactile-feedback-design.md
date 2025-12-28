# Click Wheel Tactile Feedback Design

## Overview

Add physical feedback to the click wheel to make it feel like pressing a real iPod Shuffle. The outer wheel tilts toward whichever button is pressed, and the center play/pause button depresses inward.

## Configuration

All feedback parameters are configurable via a single struct:

```swift
struct ClickWheelFeedback {
    // Wheel tilt
    static let tiltAngle: Double = 10  // degrees (exaggerated)
    static let springResponse: Double = 0.3
    static let springDampingFraction: Double = 0.6

    // Center button depression
    static let centerPressScale: Double = 0.92
    static let centerPressedShadowRadius: Double = 2
    static let centerPressedShadowY: Double = 1
    static let centerNormalShadowRadius: Double = 8
    static let centerNormalShadowY: Double = 4
}
```

## Wheel Tilt Mechanism

### Press Position Enum

```swift
enum WheelPressPosition {
    case none, top, bottom, left, right

    var rotationAxis: (x: CGFloat, y: CGFloat, z: CGFloat) {
        switch self {
        case .none: return (0, 0, 0)
        case .top: return (1, 0, 0)      // tilt forward
        case .bottom: return (-1, 0, 0)  // tilt backward
        case .left: return (0, -1, 0)    // tilt left
        case .right: return (0, 1, 0)    // tilt right
        }
    }
}
```

### Button Mapping

| Button | Position | Tilt Direction |
|--------|----------|----------------|
| Volume Up | top | Forward (top edge sinks in) |
| Volume Down | bottom | Backward (bottom edge sinks in) |
| Skip Back | left | Left (left edge sinks in) |
| Skip Forward | right | Right (right edge sinks in) |

### Implementation

`ClickWheelView` tracks press state and applies 3D rotation:

```swift
@State private var pressPosition: WheelPressPosition = .none

// Applied to the wheel ZStack
.rotation3DEffect(
    .degrees(pressPosition != .none ? ClickWheelFeedback.tiltAngle : 0),
    axis: pressPosition.rotationAxis,
    perspective: 0.3
)
.animation(.spring(response: 0.3, dampingFraction: 0.6), value: pressPosition)
```

## Center Button Depression

`PlayPauseButton` tracks its own pressed state via gesture:

```swift
@State private var isPressed = false

// Gesture to detect press
.simultaneousGesture(
    DragGesture(minimumDistance: 0)
        .onChanged { _ in isPressed = true }
        .onEnded { _ in isPressed = false }
)

// Visual transforms
.scaleEffect(isPressed ? ClickWheelFeedback.centerPressScale : 1.0)
.shadow(
    color: .black.opacity(0.1),
    radius: isPressed ? ClickWheelFeedback.centerPressedShadowRadius : ClickWheelFeedback.centerNormalShadowRadius,
    x: 0,
    y: isPressed ? ClickWheelFeedback.centerPressedShadowY : ClickWheelFeedback.centerNormalShadowY
)
```

## Button-to-Wheel Communication

`ClickWheelButton` reports press state to parent via callback:

```swift
struct ClickWheelButton: View {
    let systemName: String
    let action: () -> Void
    var onPressChanged: ((Bool) -> Void)? = nil
    var wheelStyle: ShuffleTheme.WheelStyle = .light

    @State private var isPressed = false

    var body: some View {
        // ... existing button code
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
                }
        )
    }
}
```

## Files to Modify

1. **Shfl/Views/Components/ClickWheelFeedback.swift** (new) - Configuration struct and enum
2. **Shfl/Views/Components/ClickWheelButton.swift** - Add press state tracking and callback
3. **Shfl/Views/Components/ClickWheelView.swift** - Add tilt rotation based on press position
4. **Shfl/Views/Components/PlayPauseButton.swift** - Add depression effect
