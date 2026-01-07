# ClickWheel Authentic Redesign

## Overview

Rework the ClickWheelView to match the real iPod Shuffle 4th generation appearance with proper proportions, theme-accurate colors, and a glossy shiny effect.

## Design Decisions

### Wheel Ring Color (Contrasting)
- **Colored themes (blue, green, orange, pink):** White/silver ring
- **Silver theme:** Black/dark ring

This matches the real iPod Shuffle lineup where colored devices had silver click wheels and the silver device had a dark click wheel.

### Center Button Color
The center button background matches the theme body color directly (e.g., pink button on pink theme).

### Icon Colors

| Theme  | Wheel Ring | Wheel Icons      | Center Button Icon |
|--------|------------|------------------|-------------------|
| Silver | Dark/Black | White            | Black             |
| Blue   | White      | Gray (0.3)       | Gray (0.3)        |
| Green  | White      | Gray (0.3)       | Gray (0.3)        |
| Orange | White      | Gray (0.3)       | Gray (0.3)        |
| Pink   | White      | Gray (0.3)       | Gray (0.3)        |

### Proportions
- Wheel outer diameter: 280pt (unchanged)
- Center button: 130pt (was 80pt) — ~46% of wheel diameter
- Ring thickness: ~75pt (was 100pt)

This creates the narrower ring appearance seen on the real device.

### Shiny/Glossy Effect
A subtle linear gradient overlay from top to center simulating light reflection:
- White ring: `Color.white.opacity(0.4)` → `Color.clear`
- Dark ring: `Color.white.opacity(0.15)` → `Color.clear`

## Implementation Changes

### ShuffleTheme.swift
Add new property:
```swift
let centerButtonIconColor: Color
```

Update theme definitions with appropriate center icon colors.

### ClickWheelView.swift
- Update `centerButtonSize` from 80 to 130
- Replace `wheelGradient` with solid colors + glossy overlay
- Adjust button container frames for new proportions

### PlayPauseButton.swift
- Accept theme instead of just wheelStyle
- Use `theme.bodyGradientTop` for button background
- Use `theme.centerButtonIconColor` for icon
- Scale icon size proportionally (~52pt)

### ClickWheelButton.swift
- Icon colors remain based on wheelStyle (white for dark, gray for light)
- No changes needed — already uses wheelStyle correctly

## Files to Modify
1. `Shfl/Theme/ShuffleTheme.swift`
2. `Shfl/Views/Components/ClickWheelView.swift`
3. `Shfl/Views/Components/PlayPauseButton.swift`
