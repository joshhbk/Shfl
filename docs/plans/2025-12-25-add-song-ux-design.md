# Add Song UX Redesign

## Problem

The current experience for adding songs has three issues:

1. **Unclear feedback** — The checkmark toggle is subtle. No animation, haptic, or confirmation that something happened.
2. **Confusing navigation** — Two sheets deep, "Done" appears twice with different meanings.
3. **Too many taps** — PlayerView → Manage → Add → search → tap → Done → Done is six steps.

## Design Goals

Make adding a song feel quick, deliberate, and satisfying — like packing an iPod Shuffle for a road trip. Every slot matters, and the app should celebrate your curation.

## Solution

### The Tap Interaction

One tap to toggle add/remove, with rich feedback:

| Trigger | Response |
|---------|----------|
| Finger lifts | Haptic fires immediately (medium for add, light for remove) |
| +0ms | Row background animates to blue tint (`Color.blue.opacity(0.08)`) |
| +0ms | Checkmark springs in with bounce (overshoot, then settle) |
| +0ms | Capacity bar animates to new fill level |
| +0ms | Undo pill slides up from bottom |

All animations ~200-300ms with ease-out or spring curves.

### Visual States

**Not added (default):**
- Clear background
- Gray empty circle icon (`Color.gray.opacity(0.3)`)
- Full opacity on song info

**Added (in Shfl):**
- Blue tint background (`Color.blue.opacity(0.08)`)
- Blue filled checkmark circle
- Full opacity

**Already added in search results:**
- Stay inline at natural search position (not moved to top)
- Tinted background makes them scannable

**Capacity full (120 songs):**
- Non-added rows dimmed (`opacity(0.5)`)
- Tapping triggers "nope" bounce animation
- No error alert — physical feedback only

### Capacity Indicator

Replace text-only indicator with visual progress:

- Slim progress bar (4-6pt height) at top of search view
- Background track in light gray, fill in blue
- Text label beside it: "42 / 120"
- Fill animates with spring curve when songs added/removed

**Milestones:**

| Count | Feedback |
|-------|----------|
| 1 | Stronger haptic, bar "pops" into existence |
| 50 | Celebratory haptic pattern (three quick taps) |
| 100 | Same pattern |
| 120 | Bar turns green, text shows "Your Shfl is ready!" |

### Undo Pill

Minimal custom component (no library):

- Dark capsule (`Color.black.opacity(0.85)`) at bottom of screen
- Text: "Added to Shfl · Undo" or "Removed · Undo"
- Slides up with spring animation
- Stays 3 seconds, then slides away
- New actions replace previous (no stacking)
- Tapping "Undo" reverses the action with inverse animations

Designed to be easy to delete if it doesn't feel right in practice.

### Navigation Simplification

**Before:**
```
PlayerView → "Manage Songs" → ManageView → "+" → SongPickerView → Done → Done
```
(6 taps, two "Done" buttons)

**After:**
```
PlayerView → "+" → SongPickerView → Done
```
(3 taps, one "Done")

**Changes:**
- Add "+" button to PlayerView (top-right, near capacity indicator)
- "+" opens SongPickerView directly as a sheet
- ManageView remains accessible via "Manage Songs" for viewing/removing
- Consider renaming to "View Library" or "Edit Songs"

## Components to Build/Modify

1. `SongRow.swift` — Add animations, haptics, background state
2. `CapacityProgressBar.swift` — New component replacing text indicator
3. `UndoPill.swift` — New minimal toast component
4. `PlayerView.swift` — Add "+" button, wire up direct sheet
5. `SongPickerView.swift` — Use new capacity bar, integrate undo pill

## Open Questions

- Sound effect on add? (Decided: optional, can add later)
- Exact spring animation parameters? (Will tune during implementation)
