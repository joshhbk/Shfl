# Song UX Redesign Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Improve the add-song experience with rich visual feedback, haptics, undo support, and simplified navigation.

**Architecture:** Build four new components (CapacityProgressBar, UndoPill, AnimatedSongRow wrapper, and direct add button in PlayerView). Modify SongRow to support animated states. Use Environment for undo state propagation. Composition over configuration throughout.

**Tech Stack:** SwiftUI, Combine, UIKit (for haptics via UIImpactFeedbackGenerator)

---

## Task 1: Create CapacityProgressBar Component

**Files:**
- Create: `Shfl/Views/Components/CapacityProgressBar.swift`
- Test: `ShflTests/Views/CapacityProgressBarTests.swift`

**Step 1: Write the failing test**

```swift
import XCTest
import SwiftUI
@testable import Shfl

final class CapacityProgressBarTests: XCTestCase {
    func testProgressCalculation() {
        // Test that progress is calculated correctly
        let progress = CapacityProgressBar.calculateProgress(current: 60, maximum: 120)
        XCTAssertEqual(progress, 0.5, accuracy: 0.001)
    }

    func testProgressAtZero() {
        let progress = CapacityProgressBar.calculateProgress(current: 0, maximum: 120)
        XCTAssertEqual(progress, 0.0, accuracy: 0.001)
    }

    func testProgressAtFull() {
        let progress = CapacityProgressBar.calculateProgress(current: 120, maximum: 120)
        XCTAssertEqual(progress, 1.0, accuracy: 0.001)
    }

    func testMilestoneDetection() {
        XCTAssertTrue(CapacityProgressBar.isMilestone(1))
        XCTAssertTrue(CapacityProgressBar.isMilestone(50))
        XCTAssertTrue(CapacityProgressBar.isMilestone(100))
        XCTAssertTrue(CapacityProgressBar.isMilestone(120))
        XCTAssertFalse(CapacityProgressBar.isMilestone(42))
    }
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:ShflTests/CapacityProgressBarTests 2>&1 | xcpretty`
Expected: FAIL with "No such module 'Shfl'" or "cannot find 'CapacityProgressBar' in scope"

**Step 3: Write minimal implementation**

```swift
import SwiftUI

struct CapacityProgressBar: View {
    let current: Int
    let maximum: Int

    private var progress: Double {
        Self.calculateProgress(current: current, maximum: maximum)
    }

    private var isFull: Bool {
        current >= maximum
    }

    var body: some View {
        HStack(spacing: 12) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Track
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.gray.opacity(0.2))

                    // Fill
                    RoundedRectangle(cornerRadius: 2)
                        .fill(isFull ? Color.green : Color.blue)
                        .frame(width: geometry.size.width * progress)
                        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: progress)
                }
            }
            .frame(height: 6)

            Text(isFull ? "Ready!" : "\(current) / \(maximum)")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(isFull ? .green : .secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Static Helpers (for testing)

    static func calculateProgress(current: Int, maximum: Int) -> Double {
        guard maximum > 0 else { return 0 }
        return Double(current) / Double(maximum)
    }

    static func isMilestone(_ count: Int) -> Bool {
        [1, 50, 100, 120].contains(count)
    }
}

#Preview {
    VStack(spacing: 20) {
        CapacityProgressBar(current: 0, maximum: 120)
        CapacityProgressBar(current: 42, maximum: 120)
        CapacityProgressBar(current: 100, maximum: 120)
        CapacityProgressBar(current: 120, maximum: 120)
    }
    .padding()
}
```

**Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:ShflTests/CapacityProgressBarTests 2>&1 | xcpretty`
Expected: PASS

**Step 5: Commit**

```bash
git add Shfl/Views/Components/CapacityProgressBar.swift ShflTests/Views/CapacityProgressBarTests.swift
git commit -m "feat: add CapacityProgressBar component with progress visualization"
```

---

## Task 2: Create HapticFeedback Utility

**Files:**
- Create: `Shfl/Utilities/HapticFeedback.swift`
- Test: Manual testing only (haptics require device)

**Step 1: Write the implementation**

```swift
import UIKit

enum HapticFeedback {
    case light
    case medium
    case heavy
    case success
    case warning
    case error
    case milestone

    func trigger() {
        switch self {
        case .light:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .medium:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .heavy:
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        case .success:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .warning:
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .error:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        case .milestone:
            // Three quick taps for celebration
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.prepare()
            generator.impactOccurred()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                generator.impactOccurred()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                generator.impactOccurred()
            }
        }
    }
}
```

**Step 2: Commit**

```bash
git add Shfl/Utilities/HapticFeedback.swift
git commit -m "feat: add HapticFeedback utility for tactile feedback"
```

---

## Task 3: Create UndoPill Component

**Files:**
- Create: `Shfl/Views/Components/UndoPill.swift`
- Test: `ShflTests/Views/UndoPillTests.swift`

**Step 1: Write the failing test**

```swift
import XCTest
import SwiftUI
@testable import Shfl

final class UndoPillTests: XCTestCase {
    func testAddedMessage() {
        let message = UndoPill.message(for: .added, songTitle: "Bohemian Rhapsody")
        XCTAssertEqual(message, "Added to Shfl")
    }

    func testRemovedMessage() {
        let message = UndoPill.message(for: .removed, songTitle: "Stairway to Heaven")
        XCTAssertEqual(message, "Removed")
    }
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:ShflTests/UndoPillTests 2>&1 | xcpretty`
Expected: FAIL with "cannot find 'UndoPill' in scope"

**Step 3: Write minimal implementation**

```swift
import SwiftUI

enum UndoAction {
    case added
    case removed
}

struct UndoState: Equatable {
    let action: UndoAction
    let song: Song
    let timestamp: Date

    init(action: UndoAction, song: Song) {
        self.action = action
        self.song = song
        self.timestamp = Date()
    }
}

struct UndoPill: View {
    let state: UndoState
    let onUndo: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(Self.message(for: state.action, songTitle: state.song.title))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)

            Text("·")
                .foregroundStyle(.white.opacity(0.5))

            Button(action: onUndo) {
                Text("Undo")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.85))
        )
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Static Helpers (for testing)

    static func message(for action: UndoAction, songTitle: String) -> String {
        switch action {
        case .added:
            return "Added to Shfl"
        case .removed:
            return "Removed"
        }
    }
}

#Preview {
    ZStack {
        Color.gray.opacity(0.3)

        VStack {
            Spacer()
            UndoPill(
                state: UndoState(
                    action: .added,
                    song: Song(id: "1", title: "Bohemian Rhapsody", artist: "Queen", albumTitle: "A Night at the Opera", artworkURL: nil)
                ),
                onUndo: {},
                onDismiss: {}
            )
            .padding(.bottom, 32)
        }
    }
    .ignoresSafeArea()
}
```

**Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:ShflTests/UndoPillTests 2>&1 | xcpretty`
Expected: PASS

**Step 5: Commit**

```bash
git add Shfl/Views/Components/UndoPill.swift ShflTests/Views/UndoPillTests.swift
git commit -m "feat: add UndoPill component for undo feedback"
```

---

## Task 4: Create UndoManager for Song Actions

**Files:**
- Create: `Shfl/ViewModels/SongUndoManager.swift`
- Test: `ShflTests/ViewModels/SongUndoManagerTests.swift`

**Step 1: Write the failing test**

```swift
import XCTest
@testable import Shfl

@MainActor
final class SongUndoManagerTests: XCTestCase {
    var undoManager: SongUndoManager!

    override func setUp() {
        undoManager = SongUndoManager()
    }

    func testRecordAction() {
        let song = Song(id: "1", title: "Test", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        undoManager.recordAction(.added, song: song)

        XCTAssertNotNil(undoManager.currentState)
        XCTAssertEqual(undoManager.currentState?.action, .added)
        XCTAssertEqual(undoManager.currentState?.song.id, "1")
    }

    func testAutoDisappearAfterTimeout() async throws {
        let song = Song(id: "1", title: "Test", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        undoManager.recordAction(.added, song: song, autoHideDelay: 0.1)

        XCTAssertNotNil(undoManager.currentState)

        try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds

        XCTAssertNil(undoManager.currentState)
    }

    func testNewActionReplacesOld() {
        let song1 = Song(id: "1", title: "Song 1", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        let song2 = Song(id: "2", title: "Song 2", artist: "Artist", albumTitle: "Album", artworkURL: nil)

        undoManager.recordAction(.added, song: song1)
        undoManager.recordAction(.removed, song: song2)

        XCTAssertEqual(undoManager.currentState?.song.id, "2")
        XCTAssertEqual(undoManager.currentState?.action, .removed)
    }

    func testDismiss() {
        let song = Song(id: "1", title: "Test", artist: "Artist", albumTitle: "Album", artworkURL: nil)
        undoManager.recordAction(.added, song: song)
        undoManager.dismiss()

        XCTAssertNil(undoManager.currentState)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:ShflTests/SongUndoManagerTests 2>&1 | xcpretty`
Expected: FAIL with "cannot find 'SongUndoManager' in scope"

**Step 3: Write minimal implementation**

```swift
import Combine
import SwiftUI

@MainActor
final class SongUndoManager: ObservableObject {
    @Published private(set) var currentState: UndoState?
    private var dismissTask: Task<Void, Never>?

    func recordAction(_ action: UndoAction, song: Song, autoHideDelay: TimeInterval = 3.0) {
        dismissTask?.cancel()

        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            currentState = UndoState(action: action, song: song)
        }

        dismissTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(autoHideDelay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            dismiss()
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) {
            currentState = nil
        }
    }
}
```

**Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:ShflTests/SongUndoManagerTests 2>&1 | xcpretty`
Expected: PASS

**Step 5: Commit**

```bash
git add Shfl/ViewModels/SongUndoManager.swift ShflTests/ViewModels/SongUndoManagerTests.swift
git commit -m "feat: add SongUndoManager for tracking undoable actions"
```

---

## Task 5: Update SongRow with Animated States and Haptics

**Files:**
- Modify: `Shfl/Views/Components/SongRow.swift`
- Test: `ShflTests/Views/SongRowTests.swift`

**Step 1: Write the failing test**

```swift
import XCTest
import SwiftUI
@testable import Shfl

final class SongRowTests: XCTestCase {
    func testSelectedBackgroundColor() {
        let color = SongRow.backgroundColor(isSelected: true)
        // Blue with 0.08 opacity
        XCTAssertEqual(color, Color.blue.opacity(0.08))
    }

    func testUnselectedBackgroundColor() {
        let color = SongRow.backgroundColor(isSelected: false)
        XCTAssertEqual(color, Color.clear)
    }

    func testDisabledOpacity() {
        XCTAssertEqual(SongRow.rowOpacity(isSelected: false, isAtCapacity: true), 0.5)
        XCTAssertEqual(SongRow.rowOpacity(isSelected: true, isAtCapacity: true), 1.0)
        XCTAssertEqual(SongRow.rowOpacity(isSelected: false, isAtCapacity: false), 1.0)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:ShflTests/SongRowTests 2>&1 | xcpretty`
Expected: FAIL with "Type 'SongRow' has no member 'backgroundColor'" or similar

**Step 3: Update SongRow implementation**

Replace content of `Shfl/Views/Components/SongRow.swift`:

```swift
import SwiftUI

struct SongRow: View {
    let song: Song
    let isSelected: Bool
    let isAtCapacity: Bool
    let onToggle: () -> Void

    @State private var isPressed = false
    @State private var showNope = false

    init(
        song: Song,
        isSelected: Bool,
        isAtCapacity: Bool = false,
        onToggle: @escaping () -> Void
    ) {
        self.song = song
        self.isSelected = isSelected
        self.isAtCapacity = isAtCapacity
        self.onToggle = onToggle
    }

    var body: some View {
        Button(action: handleTap) {
            HStack(spacing: 12) {
                SongDisplay(song: song)

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isSelected ? .blue : .gray.opacity(0.3))
                    .scaleEffect(isPressed ? 0.9 : 1.0)
                    .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isSelected)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .background(Self.backgroundColor(isSelected: isSelected))
            .contentShape(Rectangle())
            .opacity(Self.rowOpacity(isSelected: isSelected, isAtCapacity: isAtCapacity))
            .offset(x: showNope ? -8 : 0)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.2, dampingFraction: 0.5), value: isSelected)
        .animation(.default, value: showNope)
    }

    private func handleTap() {
        if !isSelected && isAtCapacity {
            // "Nope" bounce animation
            HapticFeedback.warning.trigger()
            withAnimation(.easeInOut(duration: 0.05).repeatCount(3, autoreverses: true)) {
                showNope = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                showNope = false
            }
            return
        }

        // Fire haptic immediately on tap
        if isSelected {
            HapticFeedback.light.trigger()
        } else {
            HapticFeedback.medium.trigger()
        }

        onToggle()
    }

    // MARK: - Static Helpers (for testing)

    static func backgroundColor(isSelected: Bool) -> Color {
        isSelected ? Color.blue.opacity(0.08) : Color.clear
    }

    static func rowOpacity(isSelected: Bool, isAtCapacity: Bool) -> Double {
        if isAtCapacity && !isSelected {
            return 0.5
        }
        return 1.0
    }
}

#Preview {
    VStack(spacing: 0) {
        SongRow(
            song: Song(id: "1", title: "Bohemian Rhapsody", artist: "Queen", albumTitle: "A Night at the Opera", artworkURL: nil),
            isSelected: false,
            onToggle: {}
        )
        Divider()
        SongRow(
            song: Song(id: "2", title: "Stairway to Heaven", artist: "Led Zeppelin", albumTitle: "Led Zeppelin IV", artworkURL: nil),
            isSelected: true,
            onToggle: {}
        )
        Divider()
        SongRow(
            song: Song(id: "3", title: "Hotel California", artist: "Eagles", albumTitle: "Hotel California", artworkURL: nil),
            isSelected: false,
            isAtCapacity: true,
            onToggle: {}
        )
    }
}
```

**Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:ShflTests/SongRowTests 2>&1 | xcpretty`
Expected: PASS

**Step 5: Commit**

```bash
git add Shfl/Views/Components/SongRow.swift ShflTests/Views/SongRowTests.swift
git commit -m "feat: update SongRow with animated states, haptics, and capacity handling"
```

---

## Task 6: Update SongPickerView with New Components

**Files:**
- Modify: `Shfl/Views/SongPickerView.swift`

**Step 1: Update SongPickerView to use new components**

Replace content of `Shfl/Views/SongPickerView.swift`:

```swift
import SwiftUI

struct SongPickerView: View {
    @ObservedObject var player: ShufflePlayer
    let musicService: MusicService
    let onDismiss: () -> Void

    @State private var searchText = ""
    @State private var searchResults: [Song] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @StateObject private var undoManager = SongUndoManager()

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    CapacityProgressBar(current: player.songCount, maximum: player.capacity)

                    if isSearching {
                        ProgressView("Searching...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if searchResults.isEmpty && !searchText.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                    } else if searchResults.isEmpty {
                        ContentUnavailableView(
                            "Search Your Library",
                            systemImage: "magnifyingglass",
                            description: Text("Type to search your Apple Music library")
                        )
                    } else {
                        songList
                    }
                }

                // Undo pill overlay
                if let undoState = undoManager.currentState {
                    UndoPill(
                        state: undoState,
                        onUndo: { handleUndo(undoState) },
                        onDismiss: { undoManager.dismiss() }
                    )
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Add Songs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDismiss)
                }
            }
            .searchable(text: $searchText, prompt: "Search your library")
            .onChange(of: searchText) { _, newValue in
                performSearch(query: newValue)
            }
            .alert("Error", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                if let error = errorMessage {
                    Text(error)
                }
            }
        }
    }

    private var songList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(searchResults) { song in
                    SongRow(
                        song: song,
                        isSelected: player.containsSong(id: song.id),
                        isAtCapacity: player.remainingCapacity == 0,
                        onToggle: { toggleSong(song) }
                    )
                    Divider()
                        .padding(.leading, 72)
                }
            }
        }
    }

    private func performSearch(query: String) {
        guard !query.isEmpty else {
            searchResults = []
            return
        }

        isSearching = true
        Task {
            do {
                let results = try await musicService.searchLibrary(query: query)
                await MainActor.run {
                    searchResults = results
                    isSearching = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isSearching = false
                }
            }
        }
    }

    private func toggleSong(_ song: Song) {
        if player.containsSong(id: song.id) {
            player.removeSong(id: song.id)
            undoManager.recordAction(.removed, song: song)
        } else {
            do {
                try player.addSong(song)
                undoManager.recordAction(.added, song: song)

                // Check for milestones
                if CapacityProgressBar.isMilestone(player.songCount) {
                    HapticFeedback.milestone.trigger()
                }
            } catch ShufflePlayerError.capacityReached {
                // Handled by SongRow's nope animation
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func handleUndo(_ state: UndoState) {
        switch state.action {
        case .added:
            // Undo add = remove
            player.removeSong(id: state.song.id)
            HapticFeedback.light.trigger()
        case .removed:
            // Undo remove = add back
            try? player.addSong(state.song)
            HapticFeedback.medium.trigger()
        }
        undoManager.dismiss()
    }
}
```

**Step 2: Run tests to verify nothing broke**

Run: `xcodebuild test -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | xcpretty`
Expected: All tests PASS

**Step 3: Commit**

```bash
git add Shfl/Views/SongPickerView.swift
git commit -m "feat: integrate CapacityProgressBar and UndoPill into SongPickerView"
```

---

## Task 7: Add Direct "+" Button to PlayerView

**Files:**
- Modify: `Shfl/Views/PlayerView.swift`

**Step 1: Update PlayerView to add "+" button**

Add a "+" button near the capacity indicator in PlayerView. Update the view to accept an additional callback:

In `PlayerView.swift`, update the struct:

```swift
import SwiftUI

struct PlayerView: View {
    @ObservedObject var player: ShufflePlayer
    let onManageTapped: () -> Void
    let onAddTapped: () -> Void

    @State private var showError = false
    @State private var errorMessage = ""

    init(
        player: ShufflePlayer,
        onManageTapped: @escaping () -> Void,
        onAddTapped: @escaping () -> Void = {}
    ) {
        self.player = player
        self.onManageTapped = onManageTapped
        self.onAddTapped = onAddTapped
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                backgroundGradient

                VStack(spacing: 0) {
                    // Error banner at top
                    if showError {
                        ErrorBanner(message: errorMessage) {
                            withAnimation {
                                showError = false
                            }
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    HStack {
                        Spacer()

                        CapacityIndicator(current: player.songCount, maximum: player.capacity)

                        // Add button
                        Button(action: onAddTapped) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(.blue)
                        }
                        .disabled(player.remainingCapacity == 0)
                        .opacity(player.remainingCapacity == 0 ? 0.4 : 1.0)
                        .padding(.leading, 8)

                        Spacer()
                    }
                    .padding(.top, showError ? 16 : geometry.safeAreaInsets.top + 16)

                    Spacer()

                    VStack(spacing: 48) {
                        nowPlayingSection

                        controlsSection
                    }
                    .padding(.horizontal, 32)

                    Spacer()

                    Button(action: onManageTapped) {
                        Text("Manage Songs")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, geometry.safeAreaInsets.bottom + 24)
                }
            }
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.2), value: showError)
            .onChange(of: player.playbackState) { _, newState in
                if case .error(let error) = newState {
                    errorMessage = error.localizedDescription
                    withAnimation {
                        showError = true
                    }
                }
            }
        }
    }

    // ... rest of the view remains the same
```

**Step 2: Update MainView to wire up direct add**

In `MainView.swift`, update to open picker directly:

```swift
// Add new state
@Published var showingPickerDirect = false

// Add method
func openPickerDirect() {
    showingPickerDirect = true
}

func closePickerDirect() {
    showingPickerDirect = false
    persistSongs()
}
```

Then update the view body to show the sheet:

```swift
PlayerView(player: viewModel.player) {
    viewModel.openManage()
} onAddTapped: {
    viewModel.openPickerDirect()
}
// ... existing sheet for manage view ...
.sheet(isPresented: $viewModel.showingPickerDirect) {
    SongPickerView(
        player: viewModel.player,
        musicService: viewModel.musicService,
        onDismiss: { viewModel.closePickerDirect() }
    )
}
```

**Step 3: Run tests to verify nothing broke**

Run: `xcodebuild test -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | xcpretty`
Expected: All tests PASS

**Step 4: Commit**

```bash
git add Shfl/Views/PlayerView.swift Shfl/Views/MainView.swift Shfl/ViewModels/AppViewModel.swift
git commit -m "feat: add direct '+' button to PlayerView for quick song access"
```

---

## Task 8: Add Tests Directory Structure

**Files:**
- Create: `ShflTests/Views/` directory

**Step 1: Create directory and placeholder**

```bash
mkdir -p ShflTests/Views
```

**Step 2: Commit**

```bash
git add ShflTests/Views
git commit -m "chore: add Views test directory structure"
```

---

## Task 9: Final Integration Test

**Files:**
- Modify: `ShflTests/Integration/AppFlowTests.swift`

**Step 1: Add integration test for new UX flow**

Add to existing `AppFlowTests.swift`:

```swift
func testDirectAddFromPlayerView() async throws {
    // This tests the navigation flow: PlayerView → "+" → SongPickerView → Done
    // The actual UI navigation is tested via UI tests, but we can verify the state management

    let song = Song(id: "1", title: "Test Song", artist: "Artist", albumTitle: "Album", artworkURL: nil)
    try await player.addSong(song)

    let songCount = await player.songCount
    XCTAssertEqual(songCount, 1)

    // Verify song can be removed
    await player.removeSong(id: "1")
    let afterRemove = await player.songCount
    XCTAssertEqual(afterRemove, 0)
}

func testUndoManagerIntegration() async throws {
    let undoManager = await SongUndoManager()
    let song = Song(id: "1", title: "Test", artist: "Artist", albumTitle: "Album", artworkURL: nil)

    // Record an add action
    await undoManager.recordAction(.added, song: song)

    let state = await undoManager.currentState
    XCTAssertNotNil(state)
    XCTAssertEqual(state?.action, .added)
}
```

**Step 2: Run all tests**

Run: `xcodebuild test -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | xcpretty`
Expected: All tests PASS

**Step 3: Commit**

```bash
git add ShflTests/Integration/AppFlowTests.swift
git commit -m "test: add integration tests for new song UX flow"
```

---

## Task 10: Update ManageView Button Label

**Files:**
- Modify: `Shfl/Views/ManageView.swift`

Per the design spec, consider renaming "Manage Songs" to "View Library" or "Edit Songs" in PlayerView.

**Step 1: Update label in PlayerView**

In `PlayerView.swift`, change:
```swift
Text("Manage Songs")
```
to:
```swift
Text("View Library")
```

**Step 2: Update navigation title in ManageView**

In `ManageView.swift`, change:
```swift
.navigationTitle("Your Songs")
```
to:
```swift
.navigationTitle("Library")
```

**Step 3: Run tests**

Run: `xcodebuild test -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | xcpretty`
Expected: All tests PASS

**Step 4: Commit**

```bash
git add Shfl/Views/PlayerView.swift Shfl/Views/ManageView.swift
git commit -m "refactor: rename 'Manage Songs' to 'View Library' for clarity"
```

---

## Summary

This plan implements the Song UX Redesign with:

1. **CapacityProgressBar** - Visual progress indicator replacing text-only display
2. **HapticFeedback** - Utility for tactile feedback (add, remove, milestones)
3. **UndoPill** - Toast component for undo actions
4. **SongUndoManager** - State management for undo functionality
5. **Updated SongRow** - Animated states, haptics, capacity handling
6. **Updated SongPickerView** - Integration of all new components
7. **Direct "+" Button** - Quick access from PlayerView (3 taps vs 6)
8. **Navigation Simplification** - Renamed "Manage Songs" to "View Library"

Total: 10 tasks, following TDD with frequent commits.
