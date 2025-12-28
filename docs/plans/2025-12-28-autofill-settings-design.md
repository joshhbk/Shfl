# Autofill Settings - Design Document

Add a settings screen to let users choose between autofill algorithms.

## Overview

**Algorithms:**
- **Random** - Shuffled picks from library (current behavior, default)
- **Recently Added** - Most recently added songs first, no randomness

**UI:** Segmented control in a dedicated Autofill settings view with description footer.

## Data Model

```swift
enum AutofillAlgorithm: String, CaseIterable {
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

Stored in UserDefaults via `@AppStorage("autofillAlgorithm")`, defaulting to `.random`.

## Settings UI

New `AutofillSettingsView` replaces the placeholder in `SettingsView`:

```swift
struct AutofillSettingsView: View {
    @AppStorage("autofillAlgorithm") private var algorithm: String = "random"

    var body: some View {
        Form {
            Section {
                Picker("Algorithm", selection: $algorithm) {
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
        switch AutofillAlgorithm(rawValue: algorithm) {
        case .random: return "Fills with random songs from your library."
        case .recentlyAdded: return "Fills with your most recently added songs."
        case .none: return ""
        }
    }
}
```

## Autofill Source Changes

Update `LibraryAutofillSource` to accept the algorithm:

```swift
struct LibraryAutofillSource: AutofillSource {
    private let musicService: MusicService
    private let algorithm: AutofillAlgorithm

    init(musicService: MusicService, algorithm: AutofillAlgorithm = .random) {
        self.musicService = musicService
        self.algorithm = algorithm
    }

    func fetchSongs(excluding: Set<String>, limit: Int) async throws -> [Song] {
        let fetchLimit = min(excluding.count + limit * 3, 500)
        let page = try await musicService.fetchLibrarySongs(
            sortedBy: .recentlyAdded,
            limit: fetchLimit,
            offset: 0
        )

        let available = page.songs.filter { !excluding.contains($0.id) }

        switch algorithm {
        case .random:
            return Array(available.shuffled().prefix(limit))
        case .recentlyAdded:
            return Array(available.prefix(limit))
        }
    }
}
```

## Wiring

Read setting at autofill time in `LibraryBrowserViewModel`:

```swift
func autofill() async {
    let algorithmRaw = UserDefaults.standard.string(forKey: "autofillAlgorithm") ?? "random"
    let algorithm = AutofillAlgorithm(rawValue: algorithmRaw) ?? .random

    let source = LibraryAutofillSource(
        musicService: musicService,
        algorithm: algorithm
    )

    // ... existing autofill logic
}
```

## Testing

**LibraryAutofillSource tests:**
- `.random` returns shuffled results
- `.recentlyAdded` preserves recency order
- Both respect `excluding` set and `limit`

**AutofillSettingsView tests:**
- Renders segmented control with both options
- Selection updates `@AppStorage` value
- Footer text updates based on selection

## Files to Change

1. `Shfl/Domain/Protocols/AutofillSource.swift` - Add `AutofillAlgorithm` enum
2. `Shfl/Domain/LibraryAutofillSource.swift` - Accept algorithm parameter
3. `Shfl/Views/Settings/AutofillSettingsView.swift` - New file
4. `Shfl/Views/SettingsView.swift` - Link to new settings view
5. `Shfl/ViewModels/LibraryBrowserViewModel.swift` - Read setting when autofilling
6. `ShflTests/Domain/AutofillSourceTests.swift` - Add algorithm tests
7. `ShflTests/Views/AutofillSettingsViewTests.swift` - New file
