import ShflDesign
import ShflLastFM
import SwiftUI

struct SidebarView: View {
    @Binding var selection: SidebarItem?

    var body: some View {
        List(selection: $selection) {
            ForEach(SidebarItem.allCases, id: \.self) { item in
                Label(item.title, systemImage: item.systemImage)
                    .accessibilityIdentifier(item.accessibilityIdentifier)
                    .tag(item)
            }
        }
        .environment(\.sidebarRowSize, .large)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ScrobblingStatus()
                .padding(.horizontal, Spacing.s16)
                .padding(.vertical, Spacing.s12)
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 200)
    }
}

private struct ScrobblingStatus: View {
    @Environment(LastFMAccount.self) private var lastFM

    var body: some View {
        let username = lastFM.connectionState.username
        HStack(spacing: Spacing.s8) {
            Circle()
                .fill(username == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.ok))
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
            Text(username.map { "Scrobbling as \($0)" } ?? "Last.fm not connected")
                .font(.secondaryText)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("mac.sidebar.scrobbling")
    }
}
