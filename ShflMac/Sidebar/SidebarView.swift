import ShflCore
import SwiftUI

struct SidebarView: View {
    @Binding var selection: SidebarItem?

    var body: some View {
        List(selection: $selection) {
            Section("Library") {
                ForEach(SidebarItem.library, id: \.self) { item in
                    SidebarRow(item: item)
                }
            }
            Section("Session") {
                SelectedSidebarRow()
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

private struct SelectedSidebarRow: View {
    @Environment(DraftEditing.self) private var drafting

    var body: some View {
        SidebarRow(item: .selected)
            .badge(Text("\(drafting.draft.songCount) / \(drafting.draft.capacity)").monospacedDigit())
    }
}
