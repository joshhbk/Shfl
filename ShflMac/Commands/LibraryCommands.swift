import SwiftUI

/// View › Songs, Artists and Playlists, on ⌘1, ⌘2 and ⌘3.
struct LibraryCommands: Commands {
    @FocusedValue(\.libraryPlace) private var place

    var body: some Commands {
        CommandGroup(before: .sidebar) {
            ForEach(Array(SidebarItem.allCases.enumerated()), id: \.element) { offset, item in
                Button(item.title) { place?.wrappedValue = item }
                    .keyboardShortcut(KeyEquivalent(Character(String(offset + 1))), modifiers: .command)
                    .disabled(place == nil)
            }
            Divider()
        }
    }
}

extension FocusedValues {
    @Entry var libraryPlace: Binding<SidebarItem?>?
}
