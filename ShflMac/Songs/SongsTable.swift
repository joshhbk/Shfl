import ShflCore
import SwiftUI

// Cells get actions, not environment objects: rows AppKit builds for accessibility lack the environment.
struct SongsTable: View {
    let songs: [Song]
    @Binding var sortOrder: [KeyPathComparator<Song>]
    var onReachEnd: () -> Void = {}

    @State private var selection = Set<Song.ID>()
    @Environment(DraftEditing.self) private var drafting

    var body: some View {
        let songIDsInDraft = drafting.songIDs
        Table(songs, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("") { song in
                InDraftCheckbox(
                    song: song,
                    isInDraft: songIDsInDraft.contains(song.id),
                    toggle: { drafting.toggle(song) }
                )
            }
            .width(24)

            TableColumn("Title", value: \.title) { song in
                Text(song.title)
                    .onAppear {
                        if song.id == songs.last?.id { onReachEnd() }
                    }
            }
            .width(min: 160, ideal: 260)

            TableColumn("Artist") { song in
                Text(song.artist)
            }
            .width(min: 120, ideal: 180)

            TableColumn("Album") { song in
                Text(song.albumTitle)
            }
            .width(min: 120, ideal: 180)

            TableColumn("Plays", value: \.playCount) { song in
                Text(song.playCount, format: .number)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 56, ideal: 64, max: 90)
        }
        .contextMenu(forSelectionType: Song.ID.self) { ids in
            Button("Add to Selected") { drafting.add(songs(for: ids)) }
        } primaryAction: { ids in
            drafting.add(songs(for: ids))
        }
        .focusedSceneValue(\.songSelection, SongSelection(songs: songs(for: selection)))
        .accessibilityIdentifier("mac.songs.table")
    }

    private func songs(for ids: Set<Song.ID>) -> [Song] {
        songs.filter { ids.contains($0.id) }
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
