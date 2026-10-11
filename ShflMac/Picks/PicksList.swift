import ShflCore
import ShflDesign
import SwiftUI

/// Your picks, newest first. ⌫ removes the selected rows.
struct PicksList: View {
    @State private var selection = Set<Song.ID>()
    @Environment(DraftEditing.self) private var drafting

    var body: some View {
        let picks = Array(drafting.draft.songs.reversed())
        List(selection: $selection) {
            ForEach(picks) { song in
                PickRow(song: song)
                    .listRowInsets(EdgeInsets(top: 0, leading: Spacing.s4, bottom: 0, trailing: Spacing.s4))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .onDeleteCommand {
            drafting.remove(picks.filter { selection.contains($0.id) })
        }
        .onExitCommand { selection = [] }
        .accessibilityIdentifier("mac.picks.list")
    }
}

/// A pick with its remove button. The button isn't a Tab stop: ⌫ does the same.
struct PickRow: View {
    let song: Song

    @Environment(DraftEditing.self) private var drafting

    var body: some View {
        CompactRow {
            SongArtwork(song: song, size: ArtworkSize.listRow)
            RowTitles(song.title, subtitle: song.artist)
            Button("Remove \(song.title) from Picks", systemImage: "xmark") {
                drafting.remove([song])
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.tertiary)
            .focusable(false)
            .accessibilityIdentifier("mac.picks.remove.\(song.id)")
        }
    }
}
