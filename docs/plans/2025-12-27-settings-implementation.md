# Settings Screen Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a settings screen accessible via gear icon in PlayerView top-right, replacing the CapacityIndicator.

**Architecture:** SettingsView is a standard iOS Form presented as a sheet from PlayerView. NavigationStack inside the sheet enables drilling into sub-settings. AppViewModel manages the sheet state.

**Tech Stack:** SwiftUI Form, NavigationStack, @AppStorage for future settings persistence.

---

## Task 1: Add Settings State to AppViewModel

**Files:**
- Modify: `Shfl/ViewModels/AppViewModel.swift`

**Step 1: Add showingSettings property**

Add after line 14 (`@Published var showingPickerDirect = false`):

```swift
@Published var showingSettings = false
```

**Step 2: Add open/close methods**

Add after `closePickerDirect()` method (after line 81):

```swift
func openSettings() {
    showingSettings = true
}

func closeSettings() {
    showingSettings = false
}
```

**Step 3: Commit**

```bash
git add Shfl/ViewModels/AppViewModel.swift
git commit -m "feat(settings): add showingSettings state to AppViewModel"
```

---

## Task 2: Create SettingsView

**Files:**
- Create: `Shfl/Views/SettingsView.swift`

**Step 1: Create the settings view**

```swift
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    NavigationLink {
                        Text("App Icon settings coming soon")
                            .navigationTitle("App Icon")
                    } label: {
                        Label("App Icon", systemImage: "app.badge")
                    }
                }

                Section("Playback") {
                    NavigationLink {
                        Text("Shuffle algorithm settings coming soon")
                            .navigationTitle("Shuffle Algorithm")
                    } label: {
                        Label("Shuffle Algorithm", systemImage: "shuffle")
                    }

                    NavigationLink {
                        Text("Autofill settings coming soon")
                            .navigationTitle("Autofill")
                    } label: {
                        Label("Autofill", systemImage: "text.badge.plus")
                    }
                }

                Section("Connections") {
                    NavigationLink {
                        Text("Last.fm connection coming soon")
                            .navigationTitle("Last.fm")
                    } label: {
                        Label("Last.fm", systemImage: "antenna.radiowaves.left.and.right")
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    SettingsView()
}
```

**Step 2: Commit**

```bash
git add Shfl/Views/SettingsView.swift
git commit -m "feat(settings): create SettingsView with placeholder sections"
```

---

## Task 3: Update PlayerView - Replace CapacityIndicator with Gear Button

**Files:**
- Modify: `Shfl/Views/PlayerView.swift`

**Step 1: Add settings callback to PlayerView**

Add new property after `let onAddTapped` (line 7):

```swift
let onSettingsTapped: () -> Void
```

**Step 2: Update init to include onSettingsTapped**

Replace the init (lines 36-46) with:

```swift
init(
    player: ShufflePlayer,
    musicService: MusicService,
    onManageTapped: @escaping () -> Void,
    onAddTapped: @escaping () -> Void = {},
    onSettingsTapped: @escaping () -> Void = {}
) {
    self.player = player
    self.musicService = musicService
    self.onManageTapped = onManageTapped
    self.onAddTapped = onAddTapped
    self.onSettingsTapped = onSettingsTapped
}
```

**Step 3: Replace CapacityIndicator with gear button in topBar**

Replace the `topBar` function (lines 138-155) with:

```swift
@ViewBuilder
private func topBar(geometry: GeometryProxy) -> some View {
    HStack {
        Button(action: onAddTapped) {
            HStack(spacing: 4) {
                Text("Songs")
                    .font(.system(size: 16, weight: .medium))
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(currentTheme.textColor)
        }
        Spacer()
        Button(action: onSettingsTapped) {
            Image(systemName: "gearshape")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(currentTheme.textColor)
        }
    }
    .padding(.horizontal, 20)
    .padding(.top, showError ? 16 : geometry.safeAreaInsets.top + 16)
}
```

**Step 4: Update previews**

Update the preview structs at the bottom to include the new parameter:

```swift
#Preview("Empty State") {
    let mockService = PreviewMockMusicService()
    let player = ShufflePlayer(musicService: mockService)
    return PlayerView(
        player: player,
        musicService: mockService,
        onManageTapped: {},
        onAddTapped: {},
        onSettingsTapped: {}
    )
}

#Preview("Playing") {
    let mockService = PreviewMockMusicService()
    let player = ShufflePlayer(musicService: mockService)
    return PlayerView(
        player: player,
        musicService: mockService,
        onManageTapped: {},
        onAddTapped: {},
        onSettingsTapped: {}
    )
}
```

**Step 5: Commit**

```bash
git add Shfl/Views/PlayerView.swift
git commit -m "feat(settings): replace CapacityIndicator with gear button in PlayerView"
```

---

## Task 4: Wire Up Settings Sheet in MainView

**Files:**
- Modify: `Shfl/Views/MainView.swift`

**Step 1: Add onSettingsTapped to PlayerView call**

Update the PlayerView instantiation (around line 17-22) to include the settings callback:

```swift
PlayerView(
    player: viewModel.player,
    musicService: viewModel.musicService,
    onManageTapped: { viewModel.openManage() },
    onAddTapped: { viewModel.openPickerDirect() },
    onSettingsTapped: { viewModel.openSettings() }
)
```

**Step 2: Add settings sheet presentation**

Add the settings sheet after the `.sheet(isPresented: $viewModel.showingPickerDirect)` block (after line 50):

```swift
.sheet(isPresented: $viewModel.showingSettings) {
    SettingsView()
}
```

**Step 3: Commit**

```bash
git add Shfl/Views/MainView.swift
git commit -m "feat(settings): wire up settings sheet in MainView"
```

---

## Task 5: Build and Test

**Step 1: Build the project**

```bash
xcodebuild build -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet
```

Expected: BUILD SUCCEEDED

**Step 2: Run tests**

```bash
xcodebuild test -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet
```

Expected: All tests pass

**Step 3: Final commit (if any fixes needed)**

If build/tests revealed issues, commit the fixes.

---

## Summary

After completing these tasks:
- Gear icon appears in top-right of PlayerView (CapacityIndicator removed)
- Tapping gear opens Settings sheet
- Settings has placeholder sections: Appearance, Playback, Connections
- Each section has NavigationLinks that push placeholder detail views
- Swipe down or "Done" dismisses the sheet
