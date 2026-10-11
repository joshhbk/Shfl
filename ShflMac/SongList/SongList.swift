import ShflCore
import ShflDesign
import SwiftUI

/// Every song list on the Mac. Screens choose the header and the cells in each row; the list owns selection,
/// ↩ and ⌫, paging, the selection bar, the context menu and what the Picks menu acts on.
struct SongList<Header: View, Row: View>: View {
    let songs: [Song]
    var onReachEnd: () -> Void = {}
    @ViewBuilder let header: () -> Header
    @ViewBuilder let row: (SongItem) -> Row

    @State private var selection = Set<Song.ID>()
    @Environment(DraftEditing.self) private var drafting
    @Environment(ListeningSessionHost.self) private var sessionHost

    var body: some View {
        let marks = SongMarks(
            pickedIDs: drafting.songIDs,
            isFull: drafting.draft.isAtCapacity,
            timeline: sessionHost.timeline
        )
        let selected = SongSelection(songs: songs.filter { selection.contains($0.id) }, marks: marks)
        List(selection: $selection) {
            ForEach(songs) { song in
                row(SongItem(song: song, mark: marks[song], togglePick: { drafting.toggle(song) }))
                    .listRowInsets(EdgeInsets(top: 0, leading: SongListMetrics.rowInset, bottom: 0, trailing: SongListMetrics.rowInset))
                    .onAppear {
                        if song.id == songs.last?.id { onReachEnd() }
                    }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .contentSurface()
        .safeAreaInset(edge: .top, spacing: 0) {
            SongListHeader(content: header)
        }
        .overlay(alignment: .bottom) {
            if selected.songs.count > 1 {
                SelectionBar(selection: selected, drafting: drafting)
                    .padding(.bottom, Spacing.s20)
            }
        }
        .contextMenu(forSelectionType: Song.ID.self) { ids in
            PickMenuItems(selection: SongSelection(songs: songs.filter { ids.contains($0.id) }, marks: marks), drafting: drafting)
        }
        .onKeyPress(.return) {
            guard selected.action == .add else { return .ignored }
            drafting.add(selected.songs)
            return .handled
        }
        .onDeleteCommand {
            drafting.remove(selected.songs)
        }
        .onExitCommand {
            selection = []
        }
        .focusedSceneValue(\.songSelection, selected)
        .accessibilityIdentifier("mac.songs.list")
    }
}

private struct SongListHeader<Content: View>: View {
    let content: () -> Content

    var body: some View {
        content()
            .frame(height: SongListMetrics.headerHeight)
            .padding(.horizontal, SongListMetrics.horizontalInset)
            .background(.surfaceContent)
            .overlay(alignment: .bottom) { Rectangle().fill(.hairline).frame(height: 1) }
    }
}

private struct SelectionBar: View {
    let selection: SongSelection
    let drafting: DraftEditing

    var body: some View {
        FloatingBar {
            Text("\(selection.songs.count) selected")
            switch selection.action {
            case .add:
                Button { drafting.add(selection.songs) } label: {
                    HStack(spacing: Spacing.s8) {
                        Text("Add to Picks")
                        KeyHint("↩")
                    }
                }
                .buttonStyle(.primary)
                .accessibilityIdentifier("mac.songs.selectionBar.add")
            case .remove:
                Button { drafting.remove(selection.songs) } label: {
                    HStack(spacing: Spacing.s8) {
                        Text("Remove from Picks")
                        KeyHint("⌫")
                    }
                }
                .buttonStyle(.primary)
                .accessibilityIdentifier("mac.songs.selectionBar.remove")
            case .full:
                Text("Picks are full")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("mac.songs.selectionBar.full")
            }
        }
    }
}

/// Add and Remove for a selection, in the context menu and the Picks menu.
struct PickMenuItems: View {
    let selection: SongSelection?
    let drafting: DraftEditing

    var body: some View {
        Button("Add to Picks") { drafting.add(selection?.songs ?? []) }
            .disabled(selection?.action != .add)
        Button("Remove from Picks") { drafting.remove(selection?.songs ?? []) }
            .disabled(!(selection?.canRemove ?? false))
    }
}
