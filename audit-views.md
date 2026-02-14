# Shfl View Layer Audit Report

**Date:** 2026-02-14
**Updated:** 2026-02-14 (view layer fixes complete)
**Branch:** `audit/view-layer-fixes`
**Scope:** All SwiftUI views, components, theme, and utility files in the view layer

---

## Executive Summary

The codebase is well-structured for a SwiftUI app of this size. `@Observable` is used consistently, `@State` is always `private`, views are reasonably decomposed, and performance-sensitive patterns like `.equatable()` on `SongRow` are applied where they matter. There are no deprecated API usages (`foregroundColor`, `cornerRadius`, `NavigationView`), no `AnyView` usage, and no `UIScreen.main.bounds`.

Most view-layer issues have been resolved. The remaining items are either deferred refactors, architectural observations, or acknowledged patterns.

---

## 1. State Management Audit

### 1.1 All `@State` is `private` -- PASS
### 1.2 No passed values declared as `@State` -- PASS
### 1.3 `@Binding` usage is appropriate -- PASS
### 1.4 Manual `Binding(get:set:)` for sheets -- RESOLVED (converted to `@Bindable`)
### 1.5 `selectedSongIds` tradeoff -- RESOLVED (documented with comment)

### 1.6 `LastFMSettingsView` local state mirrors service state -- Medium (Deferred)

**File:** `/Users/joshuahughes/Developer/Shfl/Shfl/Views/Settings/LastFMSettingsView.swift`, lines 6-12

Seven `@State` properties manage what is essentially a mini view model inline. The connection state (`isConnected`, `username`) is manually synced from the transport via `syncConnectionStatusOnly()`. This is a split-brain risk: if the transport's connection state changes externally (e.g., token expiry), the view won't reflect it until the next manual sync.

**Severity:** Medium
**Recommendation:** Extract a `LastFMSettingsViewModel` (an `@Observable` class) that owns this state and synchronizes with the transport. Deferred to a separate PR due to scope (7 @State -> @Observable, async sync restructure).

---

## 2. Modern API Usage -- PASS

No deprecated APIs found. All `foregroundStyle()`, `clipShape`, `NavigationStack`, two-parameter `onChange`, no `UIScreen.main.bounds`, no `AnyView`.

---

## 3. Architectural Observations

### 3.1 `PlayerView` uses `GeometryReader` only for `safeAreaInsets` -- Correct Pattern

**File:** `/Users/joshuahughes/Developer/Shfl/Shfl/Views/PlayerView.swift`, lines 50-72

The `GeometryReader` exists solely to read `safeAreaInsets`. `@Environment(\.safeAreaInsets)` is **not** a standard SwiftUI API despite what some resources claim. The current `GeometryReader` approach is the correct pattern for reading safe area insets.

**Severity:** N/A (no action needed)

### 3.2 `SongPickerView` has a large surface area -- Observation

**File:** `/Users/joshuahughes/Developer/Shfl/Shfl/Views/SongPickerView.swift`

541 lines covering browse mode switching, search, autofill, undo, capacity management, error handling, and song toggling. While the extracted subviews help, the file itself owns a lot of responsibility.

**Severity:** Low (functional, just large)
**Recommendation:** The browse/search content sections could potentially be extracted into separate files, but this is a judgement call based on team preference.

### 3.3 `SongInfoDisplay` has many parameters -- Low

**File:** `/Users/joshuahughes/Developer/Shfl/Shfl/Views/Components/SongInfoDisplay.swift`, lines 4-14

Eight parameters including closures, a boolean, and an optional. The init has default values which helps.

**Severity:** Low
**Recommendation:** Monitor if more parameters get added.

### 3.4 `VolumeController` relies on private API -- Acknowledged

**File:** `/Users/joshuahughes/Developer/Shfl/Shfl/Utilities/VolumeController.swift`, lines 24-25

Reaching into `MPVolumeView`'s subview hierarchy for the internal slider. The file has a thorough doc comment acknowledging this risk. The code handles the `nil` case gracefully.

**Severity:** Acknowledged (already documented, no action needed)

---

## 4. Summary of Remaining Findings

### Medium (Deferred)
| # | Finding | File | Action |
|---|---------|------|--------|
| 1.6 | 7 `@State` vars managing inline view model | `LastFMSettingsView.swift` | Extract to `@Observable` VM (separate PR) |

### Low / Observations
| # | Finding | File | Action |
|---|---------|------|--------|
| 3.2 | `SongPickerView` large surface area | `SongPickerView.swift` | Monitor |
| 3.3 | Many parameters on `SongInfoDisplay` | `SongInfoDisplay.swift` | Monitor |
| 3.4 | VolumeController private API | `VolumeController.swift` | Acknowledged |

---

## 5. Resolved Items (this PR)

| Finding | Resolution |
|---------|------------|
| `ForEach` with `id: \.offset` | Changed to `\.element.id` |
| `PlayerActions` recreated every render | Eliminated struct, pass closures directly |
| 9 `print()` statements in production | Wrapped in `#if DEBUG` |
| Manual `Binding(get:set:)` verbosity | Converted to `@Bindable` |
| `selectedSongIds` duplicates player state | Documented tradeoff with comment |
| Duplicate `SongPickerView` instantiation | Extracted `songPickerSheet(onDismiss:)` helper |
| Large `body` in `MainView` | Simplified via `@Bindable` + helper extraction |
| Unused `GeometryReader` in `ShuffleBodyView` | Removed |
| `CapacityProgressBar` / `CompactCapacityBar` duplication | Extracted `CapacityPulseModifier` |
| `DispatchQueue.main.asyncAfter` in views | Replaced with `Task` + `Task.sleep(for:)` |
| `.stroke()` instead of `.strokeBorder()` | Fixed |
| New haptic generators on every call | Cached as `static let` |
| Redundant `.clipShape` on `RoundedRectangle` | Removed |
| Redundant `.prefix(20)` on already-limited data | Removed |
| Inconsistent `onChange` parameter style | Fixed to `{ _, _ in }` |
| Bidirectional theme sync fragility | Added loop-prevention comment |
| Skeleton list duplication (3 copies) | Extracted `SkeletonList` view |
