# Settings Screen Design

## Overview

Add a settings section to house app configuration options. The settings should feel like "stepping out of the device" into a utility/configuration space - conceptually similar to how iPod configuration happened on your computer via iTunes, not on the device itself.

## Design Decisions

### Entry Point
- **Location:** Gear icon in top right of PlayerView
- **Replaces:** CapacityIndicator (removed from player, info still visible in ManageView)
- **Styling:** SF Symbol `gearshape`, matches weight/color of "Songs >" button on left

### Presentation
- **Method:** Standard `.sheet()` modifier
- **Navigation:** `NavigationStack` inside sheet for drilling into sub-settings
- **Dismissal:** Swipe down dismisses entire sheet (default iOS behavior)
- No `.interactiveDismissDisabled()` needed since changes save immediately

### Visual Style
- Standard iOS `Form` or `List` with grouped sections
- Native appearance - no custom styling
- Navigation title "Settings"
- Optional "Done" button in toolbar

### Initial Structure

```
APPEARANCE
├── App Icon                    ›

PLAYBACK
├── Shuffle Algorithm           ›
├── Autofill                    ›

CONNECTIONS
├── Last.fm                     ›
```

For MVP, rows are non-functional placeholders. Features added incrementally.

## Navigation Flow

```
PlayerView
    ↓ tap gear
SettingsView (sheet)
    ↓ tap a row
SubSettingView (pushed onto NavigationStack)
    ↓ swipe down OR tap back
Back to PlayerView OR SettingsView
```

## Implementation

### New Files
- `Shfl/Views/SettingsView.swift` - Main settings list

### Modified Files
- `PlayerView.swift` - Replace CapacityIndicator with gear button, add sheet
- `AppViewModel.swift` - Add `showingSettings` state and open/close methods

### State Management
- Sheet state (`showingSettings`) in `AppViewModel`
- Individual settings use `@AppStorage` for persistence

## Future Considerations

- App icon picker (APPEARANCE)
- Shuffle algorithm configuration (PLAYBACK)
- Autofill behavior settings (PLAYBACK)
- Last.fm scrobbling connection (CONNECTIONS)
- CapacityIndicator could return elsewhere if users miss it
