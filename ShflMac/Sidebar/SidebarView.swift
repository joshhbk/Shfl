import SwiftUI

struct SidebarView: View {
    @Binding var selection: SidebarItem?

    var body: some View {
        List(selection: $selection) {
            Section("Library") {
                ForEach(SidebarItem.allCases, id: \.self) { item in
                    Label(item.title, systemImage: item.systemImage)
                        .accessibilityIdentifier(item.accessibilityIdentifier)
                        .tag(item)
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 200)
    }
}
