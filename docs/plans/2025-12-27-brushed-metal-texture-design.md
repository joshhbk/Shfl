# Brushed Metal Texture - Design Document

A concentric ring brushed metal texture for PlayerView, recreating the iPod Shuffle 4th gen's distinctive machined aluminum finish with motion-reactive highlights.

## Overview

**Goal:** Add the distinctive circular brushed metal texture with concentric rings radiating from the center that the physical iPod Shuffle 4th gens had. Subtle but evocative of the original device.

**Where:** PlayerView background (not the click wheel - that was plastic on the real device)

**Themes:** All themes get the texture, tinted to match theme color. Just like the real devices - same machining, different anodized colors.

## Visual Components

1. **Base layer** - The theme's existing background color
2. **Concentric rings** - Fine circular grooves radiating from center, rendered as alternating light/dark bands with slight opacity variations
3. **Highlight overlay** - A soft radial gradient that shifts position based on device tilt, simulating light catching the machined surface

## Configuration Parameters

```swift
var brushedMetalIntensity: CGFloat  // 0.0 - 1.0, how visible the grooves are
var motionEnabled: Bool              // toggle motion-reactive highlights
var motionSensitivity: CGFloat       // 0.0 - 1.0, how much highlight shifts with tilt
```

Starting values: intensity 0.5, motion enabled, sensitivity 0.5. All configurable for easy tuning.

## Technical Approach

### Concentric Rings (Canvas)

Use SwiftUI's `Canvas` view to draw many thin concentric circles from the center outward. Each ring gets a slight opacity variation (alternating lighter/darker) to simulate machined grooves. Tinted using theme's accent color blended with the base.

### Motion Tracking (CoreMotion)

`MotionManager` class wraps `CMMotionManager` to read device attitude (pitch/roll). Published as `@Observable` class shared via environment. Updates throttled to 30Hz for battery efficiency.

### Dynamic Highlights

Soft radial gradient overlays the rings. Center position offsets based on device tilt - tilt left and the "light source" appears to move right. Uses theme-appropriate colors (slightly brighter version of base).

### Graceful Fallback

When motion unavailable (Simulator, disabled by user), highlight stays centered. No crashes or errors - just falls back to static version.

## New Files

- `Shfl/Views/Components/BrushedMetalBackground.swift` - Canvas-based texture view with highlight overlay
- `Shfl/Services/MotionManager.swift` - CoreMotion wrapper

## Integration Points

### ShuffleTheme

Extend to include brushed metal configuration:

```swift
var brushedMetalIntensity: CGFloat
var motionEnabled: Bool
var motionSensitivity: CGFloat
```

### PlayerView

Replace current background with `BrushedMetalBackground`. Minimal changes - just swapping what's behind everything.

### ShuffledApp

Add `MotionManager` to environment for app-wide access. Manager starts/stops motion updates based on active usage.

## Implementation Phases

### Phase 1: Static Concentric Rings

Build `BrushedMetalBackground` with Canvas drawing logic. Configurable intensity, tinted to theme color. No motion yet - get the visual right first.

### Phase 2: MotionManager Service

Create CoreMotion wrapper. Handle permissions, availability detection, start/stop lifecycle. Expose pitch and roll as published properties.

### Phase 3: Dynamic Highlights

Connect MotionManager to BrushedMetalBackground. Add radial gradient overlay that shifts based on tilt. Wire up motion parameters.

### Phase 4: Theme Integration & Polish

Add configuration properties to ShuffleTheme. Wire through environment. Fine-tune defaults.

## Testing

- Unit tests for ring-drawing calculations (spacing, opacity values)
- Manual testing on device for motion feel
- Visual review across all themes

## Open Questions

None at this time.
