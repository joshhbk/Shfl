import ShflCore
import SwiftUI

struct SidebarView: View {
    @Binding var selection: SidebarItem?

    @Environment(DraftEditing.self) private var drafting

    var body: some View {
        List(selection: $selection) {
            Section("Library") {
                ForEach(SidebarItem.library, id: \.self) { item in
                    SidebarRow(item: item)
                }
            }
            Section("Session") {
                SelectedSidebarRow(songCount: drafting.draft.songCount, capacity: drafting.draft.capacity)
                SidebarRow(item: .upNext)
            }
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 200)
    }
}

private struct SidebarRow: View {
    let item: SidebarItem

    var body: some View {
        Label(item.title, systemImage: item.systemImage)
            .tag(item)
            .accessibilityIdentifier(item.accessibilityIdentifier)
    }
}

// Rows get values, not environment objects: rows AppKit builds for accessibility lack the environment.
private struct SelectedSidebarRow: View {
    let songCount: Int
    let capacity: Int

    var body: some View {
        SidebarRow(item: .selected)
            .badge(Text("\(songCount) / \(capacity)").monospacedDigit())
    }
}
