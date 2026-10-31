import ShflDesign
import ShflLastFM
import SwiftUI

/// The library places, one focus stop: ↑ and ↓ move between them, ⌘1 to ⌘3 from anywhere.
struct SidebarView: View {
    @Binding var selection: SidebarItem?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s4) {
            ForEach(SidebarItem.allCases, id: \.self) { item in
                Button { selection = item } label: {
                    Label(item.title, systemImage: item.systemImage)
                }
                .buttonStyle(.sidebarRow(isSelected: item == selection))
                .focusable(false)
                .accessibilityIdentifier(item.accessibilityIdentifier)
            }
            Spacer(minLength: 0)
            ScrobblingStatus()
        }
        .padding(.horizontal, Spacing.s12)
        .padding(.top, Spacing.s4)
        .padding(.bottom, Spacing.s14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.surfaceSidebar, ignoresSafeAreaEdges: .all)
        .focusable(interactions: .edit)
        .focusEffectDisabled()
        .onKeyPress(keys: [.upArrow, .downArrow]) { press in
            move(by: press.key == .upArrow ? -1 : 1)
            return .handled
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 200)
    }

    private func move(by step: Int) {
        let places = SidebarItem.allCases
        let index = places.firstIndex(of: selection ?? .songs) ?? 0
        selection = places[min(max(index + step, 0), places.count - 1)]
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
        .padding(.horizontal, Spacing.s10)
        .accessibilityIdentifier("mac.sidebar.scrobbling")
    }
}
