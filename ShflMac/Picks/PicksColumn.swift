import ShflCore
import ShflDesign
import SwiftUI

/// What feeds the next shuffle, between the library and the player.
struct PicksColumn: View {
    @SceneStorage("picksLayout") private var layout = PicksLayout.tray
    @State private var isCelebrating = false
    @Environment(DraftEditing.self) private var drafting

    var body: some View {
        let draft = drafting.draft
        VStack(alignment: .leading, spacing: 0) {
            PicksHeader(layout: $layout)
            CountFraction(draft.songCount, of: draft.capacity)
                .foregroundStyle(isCelebrating ? AnyShapeStyle(.accentText) : AnyShapeStyle(.textPrimary), .textSecondary, .textTertiary)
            switch layout {
            case .tray:
                PicksTray()
                    .padding(.top, Spacing.s14)
                PicksActions()
                    .padding(.top, Spacing.s14)
                LatestPicks()
                    .padding(.top, Spacing.s20)
                Spacer(minLength: Spacing.s16)
            case .list:
                CapacityRule(draft.songCount, of: draft.capacity, marks: TrayMarks.ruler(draft))
                    .padding(.top, Spacing.s14)
                PicksList()
                    .padding(.top, Spacing.s10)
                PicksActions()
                    .padding(.top, Spacing.s12)
                    .padding(.bottom, Spacing.s16)
            }
            ShuffleButton()
        }
        .padding(.horizontal, Spacing.s20)
        .padding(.bottom, Spacing.s16)
        .frame(width: 300)
        .frame(maxHeight: .infinity, alignment: .top)
        .paneSurface()
        .overlay(alignment: .leading) { Rectangle().fill(.hairline).frame(width: 1) }
        .focusedSceneValue(\.picksLayout, $layout)
        .task(id: drafting.moment) { await celebrate(drafting.moment) }
        .onChange(of: drafting.moment) { _, moment in
            guard let moment else { return }
            AccessibilityNotification.Announcement(moment.announcement(capacity: draft.capacity)).post()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Picks")
        .accessibilityIdentifier("mac.picks")
    }

    private func celebrate(_ moment: PicksMoment?) async {
        isCelebrating = false
        guard case .milestone = moment?.kind else { return }
        withAnimation(.easeOut(duration: 0.2)) { isCelebrating = true }
        try? await Task.sleep(for: .milliseconds(900))
        withAnimation(.easeIn(duration: 0.4)) { isCelebrating = false }
    }
}

private extension PicksMoment {
    func announcement(capacity: Int) -> String {
        switch kind {
        case .milestone(capacity): "Picks are full, \(capacity) of \(capacity)."
        case .milestone(1): "1 pick."
        case .milestone(let count): "\(count) picks."
        case .noRoom: "Not enough room. Nothing added."
        }
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
    @Environment(LibraryPreferences.self) private var preferences

    var body: some View {
        HStack(spacing: Spacing.s8) {
            Button("Autofill") { Task { await drafting.autofill() } }
                .disabled(!drafting.canAutofill)
                .help("Fill your picks with songs from your library")
                .accessibilityIdentifier("mac.picks.autofill")
            if drafting.draft.isEmpty {
                Menu {
                    AutofillSourceItems(preferences: preferences)
                } label: {
                    HStack(spacing: Spacing.s4) {
                        Text(preferences.autofillAlgorithm.displayName)
                        Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                    }
                }
                .menuStyle(.button)
                .menuIndicator(.hidden)
                .accessibilityLabel("Autofill using: \(preferences.autofillAlgorithm.displayName)")
                .accessibilityIdentifier("mac.picks.autofillSource")
            } else {
                Button("Clear", action: drafting.clearAll)
                    .accessibilityIdentifier("mac.picks.clear")
            }
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
