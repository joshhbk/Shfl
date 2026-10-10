import ShflCore
import SwiftUI

// Only Title and Plays sort: they are the only orders the library's catalog offers.
struct SortableSongsTable<RowMenu: View>: View {
    let songs: [Song]
    @Binding var sortOrder: [KeyPathComparator<Song>]
    var onReachEnd: () -> Void = {}
    @ViewBuilder let rowMenu: ([Song]) -> RowMenu

    @State private var selection = Set<Song.ID>()
    @Environment(DraftEditing.self) private var drafting

    var body: some View {
        Table(songs, selection: $selection, sortOrder: $sortOrder) {
            SongColumns.inDraft(drafting)
            TableColumn("Title", value: \.title) { song in
                SongTitleCell(song: song, isLast: song.id == songs.last?.id, onReachEnd: onReachEnd)
            }
            .width(min: 160, ideal: 260)
            SongColumns.artist
            SongColumns.album
            TableColumn("Plays", value: \.playCount) { song in
                PlayCountCell(song: song)
            }
            .width(min: 56, ideal: 64, max: 90)
        }
        .songTableBehavior(songs: songs, selection: selection, rowMenu: rowMenu)
    }
}

// No column sorts: sorting only the loaded pages would make rows jump.
struct SongsTable<RowMenu: View>: View {
    let songs: [Song]
    var onReachEnd: () -> Void = {}
    @ViewBuilder let rowMenu: ([Song]) -> RowMenu

    @State private var selection = Set<Song.ID>()
    @Environment(DraftEditing.self) private var drafting

    var body: some View {
        Table(songs, selection: $selection) {
            SongColumns.inDraft(drafting)
            TableColumn("Title") { song in
                SongTitleCell(song: song, isLast: song.id == songs.last?.id, onReachEnd: onReachEnd)
            }
            .width(min: 160, ideal: 260)
            SongColumns.artist
            SongColumns.album
            TableColumn("Plays") { song in
                PlayCountCell(song: song)
            }
            .width(min: 56, ideal: 64, max: 90)
        }
        .songTableBehavior(songs: songs, selection: selection, rowMenu: rowMenu)
    }
}

struct AddToSelectedButton: View {
    let songs: [Song]
    let drafting: DraftEditing

    var body: some View {
        Button("Add to Selected") { drafting.add(songs) }
    }
}

struct RemoveFromSelectedButton: View {
    let songs: [Song]
    let drafting: DraftEditing

    var body: some View {
        Button("Remove from Selected") { drafting.remove(songs) }
    }
}

// Cells get values and actions, not environment objects: rows AppKit builds for accessibility lack the environment.
private enum SongColumns {
    @MainActor
    static func inDraft(_ drafting: DraftEditing) -> some TableColumnContent<Song, Never> {
        let songIDsInDraft = drafting.songIDs
        return TableColumn("") { song in
            InDraftCheckbox(
                song: song,
                isInDraft: songIDsInDraft.contains(song.id),
                toggle: { drafting.toggle(song) }
            )
        }
        .width(24)
    }

    @MainActor
    static var artist: some TableColumnContent<Song, Never> {
        TableColumn("Artist") { song in
            Text(song.artist)
        }
        .width(min: 120, ideal: 180)
    }

    @MainActor
    static var album: some TableColumnContent<Song, Never> {
        TableColumn("Album") { song in
            Text(song.albumTitle)
        }
        .width(min: 120, ideal: 180)
    }
}

private struct SongTitleCell: View {
    let song: Song
    let isLast: Bool
    let onReachEnd: () -> Void

    var body: some View {
        Text(song.title)
            .onAppear {
                if isLast { onReachEnd() }
            }
    }
}

private struct PlayCountCell: View {
    let song: Song

    var body: some View {
        Text(song.playCount, format: .number)
            .monospacedDigit()
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

private struct InDraftCheckbox: View {
    let song: Song
    let isInDraft: Bool
    let toggle: () -> Void

    var body: some View {
        Toggle(
            "In Selected",
            isOn: Binding(get: { isInDraft }, set: { _ in toggle() })
        )
        .toggleStyle(.checkbox)
        .labelsHidden()
        .accessibilityLabel("\(song.title) in Selected")
        .accessibilityIdentifier("mac.songs.inDraft.\(song.id)")
    }
}

private extension View {
    func songTableBehavior<RowMenu: View>(
        songs: [Song],
        selection: Set<Song.ID>,
        @ViewBuilder rowMenu: @escaping ([Song]) -> RowMenu
    ) -> some View {
        let inTableOrder = { (ids: Set<Song.ID>) in songs.filter { ids.contains($0.id) } }
        return contextMenu(forSelectionType: Song.ID.self) { ids in
            rowMenu(inTableOrder(ids))
        }
        .focusedSceneValue(\.songSelection, SongSelection(songs: inTableOrder(selection)))
        .accessibilityIdentifier("mac.songs.table")
    }
}
