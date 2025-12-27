# Theme Switcher Design

## Overview

Add swipeable color themes to Shfl, paying homage to the iPod Shuffle 4th generation (2010) color lineup. Users swipe horizontally on the player background to slide between themes. A random theme is selected on each app launch.

## Themes

Five themes based on the 2010 iPod Shuffle launch colors:

| Name | Body Gradient (top → bottom) | Click Wheel | Text |
|------|------------------------------|-------------|------|
| Silver | `#C0C0C0` → `#A8A8A8` | Dark | Dark |
| Blue | `#4A9BD9` → `#3A7BB0` | Light | Light |
| Green | `#7AB648` → `#5A9630` | Light | Light |
| Orange | `#F5A623` → `#D4880A` | Light | Light |
| Pink | `#E85A71` → `#C44A61` | Light | Light |

Designed for extensibility - adding 2012 colors (Purple, Yellow, Slate) or 2015 colors (Gold, Space Gray) later requires only adding new theme definitions.

## Interaction Model

### Swipe Gesture

- **Direction:** Horizontal swipe on the PlayerView background
- **Transition:** Slide transition (current theme slides out, new theme slides in)
- **Physics:** Steve Jobs-era Apple feel - momentum, spring animations
- **Boundaries:** Bounded with rubber-band bounce at edges (Silver and Pink)
- **Threshold:** Commit to new theme if drag >100pt or velocity exceeds threshold

### Visual Feedback

During the swipe:
- Current theme background offsets with the drag
- Next/previous theme peeks in from the edge
- Only 3 backgrounds rendered at once (current ± 1) for performance

### Persistence

- **Random on launch:** Each app launch selects a random theme
- **Session persistence:** Swipe changes persist for the session only
- **No settings storage:** Theme choice is ephemeral

### Discoverability

- No explicit hints or onboarding
- Random color on each launch serves as the clue that multiple colors exist
- Pure discovery - rewarding for those who find it

## Data Model

```swift
struct ShuffleTheme: Identifiable, CaseIterable {
    let id: String
    let name: String
    let bodyGradient: (top: Color, bottom: Color)
    let clickWheelStyle: ClickWheelStyle
    let textStyle: TextStyle

    enum ClickWheelStyle {
        case light  // white/gray gradient (colorful themes)
        case dark   // black/dark gray gradient (silver)
    }

    enum TextStyle {
        case light  // white text (saturated backgrounds)
        case dark   // dark text (silver background)
    }
}
```

## Theme Propagation

Environment-based injection following SwiftUI patterns:

```swift
struct ThemeKey: EnvironmentKey {
    static let defaultValue: ShuffleTheme = .silver
}

extension EnvironmentValues {
    var shuffleTheme: ShuffleTheme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}
```

Root view injects theme, components read via `@Environment(\.shuffleTheme)`.

## File Structure

### New Files

```
Shfl/Theme/
├── ShuffleTheme.swift        # Theme model with all 5 themes
└── ThemeEnvironment.swift    # Environment key + extension
```

### Modified Files

- `PlayerView.swift` - Add drag gesture, ZStack for sliding backgrounds, theme injection
- `ClickWheelView.swift` - Read theme for wheel style (light/dark)
- `NowPlayingInfo.swift` - Read theme for text color
- `CapacityIndicator.swift` - Read theme for text color
- `PlaybackProgressBar.swift` - Read theme for bar color
- `ShuffledApp.swift` - Random theme selection on launch

## Haptics

- Subtle tap when successfully swiping to a new theme
- Lighter "bump" when hitting boundaries

## Animation

- **Swipe commit:** Spring animation (response: 0.4, dampingFraction: 0.75)
- **Snap-back:** Same spring for consistency
- **Boundary rubber-band:** Increased drag resistance, snappier return

## Testing

- Unit tests for `ShuffleTheme` properties
- UI tests for swipe gesture changing background
- Manual verification of all 5 themes for contrast/readability

## Scope

Purely presentation layer - no changes to domain logic, view models, or services.
