# Library Full Celebration Design

## Overview

When a user fills their library to 120 songs - whether through autofill or manually adding the final song - they get a subtle but satisfying moment of acknowledgment inspired by the Jobs-era MacBook sleep indicator.

## Design Goals

- **Nostalgic**: Evokes the iPod/early MacBook era of Apple design
- **Restrained**: Subtle and elegant, not flashy
- **Tactile**: Combines visual and haptic feedback

## The Sequence

1. The progress bar fills to 100% and turns green (existing behavior)
2. A single firm haptic fires (the "thunk")
3. A soft white glow appears behind the bar and begins breathing
4. Two slow breath cycles (~4 seconds total)
5. Glow fades out, leaving the standard green "Ready!" state

## Animation Details

### The Breathing Glow

The glow effect is a soft white aura positioned behind the progress bar, expanding and contracting with an organic rhythm.

**Visual properties:**
- Color: White with ~40% opacity at peak brightness
- Blur radius: ~8-12pt (soft, diffused edge)
- Expansion: Glow subtly grows 2-3pt outward on "inhale", contracts on "exhale"
- The green bar remains solid and sharp on top - the glow only affects the area behind/around it

**Animation curve:**
- Uses ease-in-out (not linear) for organic, breathing feel
- Slightly longer on the "exhale" than "inhale" - mimics natural breathing

### The Haptic

A single `UIImpactFeedbackGenerator` with `.medium` style. Fires exactly once at the moment of reaching 120, before the glow begins.

### Accessibility

- Respects "Reduce Motion" setting - if enabled, skip the breathing animation but keep the haptic
- Glow has sufficient contrast against the background

## Implementation Approach

### Location

The celebration logic stays contained within `CapacityProgressBar.swift`. The component already knows `current` and `maximum`, so it can detect the "just became full" transition.

### State Management

- `@State var isShowingCelebration: Bool`
- Triggered when current hits maximum
- Auto-resets after animation completes

### New Components

- Private `BreathingGlow` view that handles the pulsing animation
- Composed behind the progress bar using a `ZStack`

### Haptic

Uses existing `HapticFeedback.swift` utility with medium impact.

### Animation

SwiftUI's `Animation.easeInOut(duration:).repeatCount(2, autoreverses: true)` for the two-cycle breathing effect.

### Reduce Motion

Check `@Environment(\.accessibilityReduceMotion)` to conditionally skip the glow while preserving the haptic.

## Edge Cases

- **Autofill overshoots then settles at 120**: Celebration fires once when we hit 120, not repeatedly as songs are rejected
- **Already at 120 on view appear**: Don't trigger - only on the *transition* to full
- **Rapid add/remove near capacity**: Gate so animation doesn't restart mid-breath

## Testing

- Unit test: `CapacityProgressBar.shouldCelebrate(previous:current:maximum:)` - returns true only on 119→120 transition
- Snapshot test: Capture glow state mid-animation
- Manual test: Verify haptic on device (haptics don't work in simulator)

## Out of Scope (YAGNI)

- No sound effects
- No celebration for other milestones (50, 100)
- No confetti, particles, or embellishments
- No persistence of "has seen celebration" state
