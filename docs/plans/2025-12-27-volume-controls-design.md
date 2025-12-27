# Volume Controls & Songs Button Design

## Summary

Transform the click wheel +/- buttons from add/remove song controls into system volume controls, and relocate the "add songs" action to a new "Songs ▸" button in the top left corner.

## Changes

### Click Wheel
- **Top button (+)**: Volume up (was: add song)
- **Bottom button (−)**: Volume down (was: remove song)
- Skip forward/back and play/pause remain unchanged

### PlayerView Top Bar
- Add "Songs ▸" text button in top left corner
- Triggers the song picker (same as old + button)
- Styled to match theme, similar to "View Library" button

**New layout:**
```
[ Songs ▸ ]                    [ 3/10 capacity ]
```

### Removed Functionality
- Remove song from player view (- button action)
- Undo pill for removed songs
- Associated state: `removedSong`, `showUndoPill`, `handleRemove()`, `handleUndo()`

## Implementation

### VolumeController Utility

New file: `Shfl/Utilities/VolumeController.swift`

Uses `MPVolumeView` to control system volume:
- Create hidden MPVolumeView
- Access internal slider to adjust volume
- Step size: 0.0625 (1/16, matching iOS default)
- Clamp between 0.0 and 1.0

### ClickWheelView Changes

Replace callbacks:
- Remove: `onAdd`, `onRemove`
- Add: `onVolumeUp`, `onVolumeDown`

### PlayerView Changes

- Add "Songs ▸" button to top bar (left side)
- Remove undo pill and related state
- Wire volume callbacks to VolumeController

## Files Affected

**Modified:**
- `Shfl/Views/Components/ClickWheelView.swift`
- `Shfl/Views/PlayerView.swift`

**New:**
- `Shfl/Utilities/VolumeController.swift`

## Design Rationale

- +/- for volume matches the original iPod click wheel
- "Songs ▸" text label echoes classic iPod menu navigation
- Removing the "remove song" feature simplifies the player view
- Users can still manage songs via the "View Library" button
