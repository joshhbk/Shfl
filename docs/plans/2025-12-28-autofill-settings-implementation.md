# Autofill Settings Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a settings screen to let users choose between Random and Recently Added autofill algorithms.

**Architecture:** Add `AutofillAlgorithm` enum, update `LibraryAutofillSource` to respect algorithm choice, create `AutofillSettingsView` with segmented picker, read setting from UserDefaults at autofill time.

**Tech Stack:** SwiftUI, Swift Testing, UserDefaults/@AppStorage

---

### Task 1: Add AutofillAlgorithm Enum

**Files:**
- Modify: `Shfl/Domain/Protocols/AutofillSource.swift:1-12`

**Step 1: Add the enum after imports**

Add this after line 1 (the import statement):

```swift
/// Algorithm options for autofill behavior
enum AutofillAlgorithm: String, CaseIterable, Sendable {
    case random = "random"
    case recentlyAdded = "recentlyAdded"

    var displayName: String {
        switch self {
        case .random: return "Random"
        case .recentlyAdded: return "Recently Added"
        }
    }
}
```

**Step 2: Build to verify it compiles**

Run: `xcodebuild -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add Shfl/Domain/Protocols/AutofillSource.swift
git commit -m "feat: add AutofillAlgorithm enum"
```

---

### Task 2: Add Algorithm Tests for LibraryAutofillSource

**Files:**
- Modify: `ShflTests/Domain/AutofillSourceTests.swift:14-82`

**Step 1: Add test for random algorithm shuffles results**

Add this test inside `LibraryAutofillSourceTests` struct (after line 77):

```swift
@Test("Random algorithm shuffles results")
func randomAlgorithmShufflesResults() async throws {
    let mockService = MockMusicService()
    // Create songs with sequential IDs
    let songs = (1...20).map { makeSong(id: "\($0)") }
    await mockService.setLibrarySongs(songs)

    let source = LibraryAutofillSource(musicService: mockService, algorithm: .random)

    // Run multiple times - at least one should differ from original order
    var foundDifferentOrder = false
    for _ in 0..<10 {
        let result = try await source.fetchSongs(excluding: [], limit: 20)
        let resultIds = result.map { $0.id }
        let originalIds = songs.map { $0.id }
        if resultIds != originalIds {
            foundDifferentOrder = true
            break
        }
    }

    #expect(foundDifferentOrder, "Random algorithm should shuffle results")
}
```

**Step 2: Add test for recently added algorithm preserves order**

Add this test after the previous one:

```swift
@Test("Recently added algorithm preserves order")
func recentlyAddedPreservesOrder() async throws {
    let mockService = MockMusicService()
    // Songs are returned in recency order from mock
    let songs = (1...10).map { makeSong(id: "\($0)") }
    await mockService.setLibrarySongs(songs)

    let source = LibraryAutofillSource(musicService: mockService, algorithm: .recentlyAdded)
    let result = try await source.fetchSongs(excluding: [], limit: 10)

    let resultIds = result.map { $0.id }
    let expectedIds = songs.map { $0.id }
    #expect(resultIds == expectedIds, "Recently added should preserve order")
}
```

**Step 3: Add test for default algorithm is random**

Add this test after the previous one:

```swift
@Test("Default algorithm is random")
func defaultAlgorithmIsRandom() async throws {
    let mockService = MockMusicService()
    let songs = (1...5).map { makeSong(id: "\($0)") }
    await mockService.setLibrarySongs(songs)

    // Init without algorithm parameter
    let source = LibraryAutofillSource(musicService: mockService)
    let result = try await source.fetchSongs(excluding: [], limit: 5)

    // Should still work (not crash)
    #expect(result.count == 5)
}
```

**Step 4: Run tests to verify they fail**

Run: `xcodebuild -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | grep -E "randomAlgorithmShufflesResults|recentlyAddedPreservesOrder|defaultAlgorithmIsRandom"`
Expected: Compile errors about missing `algorithm` parameter

**Step 5: Commit the failing tests**

```bash
git add ShflTests/Domain/AutofillSourceTests.swift
git commit -m "test: add algorithm behavior tests for LibraryAutofillSource"
```

---

### Task 3: Update LibraryAutofillSource to Accept Algorithm

**Files:**
- Modify: `Shfl/Domain/LibraryAutofillSource.swift:1-27`

**Step 1: Add algorithm property and update init**

Replace lines 4-9 with:

```swift
struct LibraryAutofillSource: AutofillSource {
    private let musicService: MusicService
    private let algorithm: AutofillAlgorithm

    init(musicService: MusicService, algorithm: AutofillAlgorithm = .random) {
        self.musicService = musicService
        self.algorithm = algorithm
    }
```

**Step 2: Update fetchSongs to respect algorithm**

Replace lines 20-25 (the filter/shuffle/return logic) with:

```swift
        // Filter out excluded songs
        let available = page.songs.filter { !excluding.contains($0.id) }

        // Apply algorithm
        switch algorithm {
        case .random:
            return Array(available.shuffled().prefix(limit))
        case .recentlyAdded:
            return Array(available.prefix(limit))
        }
```

**Step 3: Run tests to verify they pass**

Run: `xcodebuild -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | grep -E "passed|failed" | tail -20`
Expected: All tests pass

**Step 4: Commit**

```bash
git add Shfl/Domain/LibraryAutofillSource.swift
git commit -m "feat: LibraryAutofillSource respects algorithm parameter"
```

---

### Task 4: Create AutofillSettingsView

**Files:**
- Create: `Shfl/Views/Settings/AutofillSettingsView.swift`

**Step 1: Create the settings view file**

```swift
import SwiftUI

struct AutofillSettingsView: View {
    @AppStorage("autofillAlgorithm") private var algorithmRaw: String = AutofillAlgorithm.random.rawValue

    private var algorithm: AutofillAlgorithm {
        AutofillAlgorithm(rawValue: algorithmRaw) ?? .random
    }

    var body: some View {
        Form {
            Section {
                Picker("Algorithm", selection: $algorithmRaw) {
                    ForEach(AutofillAlgorithm.allCases, id: \.rawValue) { algo in
                        Text(algo.displayName).tag(algo.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text(algorithmDescription)
            }
        }
        .navigationTitle("Autofill")
    }

    private var algorithmDescription: String {
        switch algorithm {
        case .random:
            return "Fills with random songs from your library."
        case .recentlyAdded:
            return "Fills with your most recently added songs."
        }
    }
}

#Preview {
    NavigationStack {
        AutofillSettingsView()
    }
}
```

**Step 2: Build to verify it compiles**

Run: `xcodebuild -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add Shfl/Views/Settings/AutofillSettingsView.swift
git commit -m "feat: add AutofillSettingsView with segmented picker"
```

---

### Task 5: Wire Up SettingsView to AutofillSettingsView

**Files:**
- Modify: `Shfl/Views/SettingsView.swift:26-31`

**Step 1: Replace the placeholder NavigationLink**

Replace lines 26-31 (the Autofill NavigationLink) with:

```swift
                    NavigationLink {
                        AutofillSettingsView()
                    } label: {
                        Label("Autofill", systemImage: "text.badge.plus")
                    }
```

**Step 2: Build to verify it compiles**

Run: `xcodebuild -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 3: Run existing tests**

Run: `xcodebuild -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | grep -E "passed|failed" | tail -10`
Expected: All tests pass

**Step 4: Commit**

```bash
git add Shfl/Views/SettingsView.swift
git commit -m "feat: wire SettingsView to AutofillSettingsView"
```

---

### Task 6: Update SongPickerView to Read Algorithm Setting

**Files:**
- Modify: `Shfl/Views/SongPickerView.swift:74-78`

**Step 1: Update the autofill button action**

Replace lines 74-78 (the Autofill button action) with:

```swift
                        Button("Autofill") {
                            Task {
                                let algorithmRaw = UserDefaults.standard.string(forKey: "autofillAlgorithm") ?? "random"
                                let algorithm = AutofillAlgorithm(rawValue: algorithmRaw) ?? .random
                                let source = LibraryAutofillSource(musicService: musicService, algorithm: algorithm)
                                await viewModel.autofill(into: player, using: source)
                            }
                        }
```

**Step 2: Build to verify it compiles**

Run: `xcodebuild -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 3: Run all tests**

Run: `xcodebuild -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | grep -E "passed|failed" | tail -10`
Expected: All tests pass

**Step 4: Commit**

```bash
git add Shfl/Views/SongPickerView.swift
git commit -m "feat: SongPickerView reads autofill algorithm from settings"
```

---

### Task 7: Add AutofillSettingsView Tests

**Files:**
- Create: `ShflTests/Views/AutofillSettingsViewTests.swift`

**Step 1: Create the test file**

```swift
import SwiftUI
import Testing
@testable import Shfl

@Suite("AutofillSettingsView Tests")
struct AutofillSettingsViewTests {
    @Test("Default algorithm is random")
    func defaultAlgorithmIsRandom() {
        // Clear any existing value
        UserDefaults.standard.removeObject(forKey: "autofillAlgorithm")

        let storedValue = UserDefaults.standard.string(forKey: "autofillAlgorithm")
        #expect(storedValue == nil, "No value should be stored by default")

        // The view should default to random when nil
        let algorithm = AutofillAlgorithm(rawValue: storedValue ?? "random")
        #expect(algorithm == .random)
    }

    @Test("Algorithm enum has correct display names")
    func algorithmDisplayNames() {
        #expect(AutofillAlgorithm.random.displayName == "Random")
        #expect(AutofillAlgorithm.recentlyAdded.displayName == "Recently Added")
    }

    @Test("Algorithm enum has all expected cases")
    func algorithmCases() {
        let cases = AutofillAlgorithm.allCases
        #expect(cases.count == 2)
        #expect(cases.contains(.random))
        #expect(cases.contains(.recentlyAdded))
    }

    @Test("Algorithm raw values are stable")
    func algorithmRawValues() {
        #expect(AutofillAlgorithm.random.rawValue == "random")
        #expect(AutofillAlgorithm.recentlyAdded.rawValue == "recentlyAdded")
    }
}
```

**Step 2: Run tests to verify they pass**

Run: `xcodebuild -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | grep "AutofillSettingsView"`
Expected: All AutofillSettingsView tests pass

**Step 3: Commit**

```bash
git add ShflTests/Views/AutofillSettingsViewTests.swift
git commit -m "test: add AutofillSettingsView tests"
```

---

### Task 8: Final Verification

**Step 1: Run full test suite**

Run: `xcodebuild -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | tail -30`
Expected: All tests pass

**Step 2: Verify test count increased**

Run: `xcodebuild -scheme Shfl -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | grep -c "passed"`
Expected: More than 147 (baseline was 147)

**Step 3: Done**

Feature complete. Use superpowers:finishing-a-development-branch to merge or create PR.
