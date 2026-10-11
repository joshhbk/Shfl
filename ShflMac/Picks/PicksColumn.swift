import ShflCore
import ShflDesign
import SwiftUI

/// What feeds the next shuffle, between the library and the player.
struct PicksColumn: View {
    @SceneStorage("picksLayout") private var layout = PicksLayout.tray
    @Environment(DraftEditing.self) private var drafting

    var body: some View {
        let draft = drafting.draft
        VStack(alignment: .leading, spacing: 0) {
            PicksHeader(layout: $layout)
            CountFraction(draft.songCount, of: draft.capacity)
            switch layout {
            case .tray:
                PicksTray()
                    .padding(.top, Spacing.s14)
                PicksActions()
                    .padding(.top, Spacing.s14)
                LatestPicks()
                    .padding(.top, Spacing.s20)
                Spacer(minLength: 0)
            case .list:
                CapacityRule(draft.songCount, of: draft.capacity, marks: TrayMarks.ruler(draft))
                    .padding(.top, Spacing.s14)
                PicksList()
                    .padding(.top, Spacing.s10)
                PicksActions()
                    .padding(.top, Spacing.s12)
            }
        }
        .padding(.horizontal, Spacing.s20)
        .padding(.bottom, Spacing.s16)
        .frame(width: 300)
        .frame(maxHeight: .infinity, alignment: .top)
        .paneSurface()
        .overlay(alignment: .leading) { Rectangle().fill(.hairline).frame(width: 1) }
        .focusedSceneValue(\.picksLayout, $layout)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Picks")
        .accessibilityIdentifier("mac.picks")
    }
}

private struct PicksHeader: View {
    @Binding var layout: PicksLayout

    var body: some View {
        HStack {
            Text("Picks")
                .font(.columnTitle)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Picker("Show Picks As", selection: $layout) {
                Label("Tray", systemImage: "square.grid.3x3.fill").tag(PicksLayout.tray)
                Label("List", systemImage: "list.bullet").tag(PicksLayout.list)
            }
            .pickerStyle(.segmented)
            .labelStyle(.iconOnly)
            .labelsHidden()
            .fixedSize()
            .accessibilityIdentifier("mac.picks.layout")
        }
        .frame(height: 52)
    }
}

private struct PicksActions: View {
    @Environment(DraftEditing.self) private var drafting

    var body: some View {
        HStack(spacing: Spacing.s8) {
            Button("Autofill") { Task { await drafting.autofill() } }
                .disabled(!drafting.canAutofill)
                .help("Fill your picks with songs from your library")
                .accessibilityIdentifier("mac.picks.autofill")
            Button("Clear", action: drafting.clearAll)
                .disabled(drafting.draft.isEmpty)
                .accessibilityIdentifier("mac.picks.clear")
        }
        .buttonStyle(.quiet)
        .controlSize(.small)
    }
}

enum TrayMarks {
    /// The milestones the ruler names; the first pick is a milestone but not a row end.
    static func ruler(_ draft: SessionDraftStore) -> [Int] {
        draft.milestones.filter { $0 > 1 }.sorted()
    }
}
