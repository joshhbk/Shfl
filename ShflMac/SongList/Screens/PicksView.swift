import ShflCore
import ShflDesign
import SwiftUI

/// Your picks, newest first.
struct PicksView: View {
    @Environment(DraftEditing.self) private var drafting
    @Environment(LibraryBrowser.self) private var browser

    private static let columns: [ListColumn] = [.artwork, .title, .detail, SongStat.plays.column, .time, .accessory]

    var body: some View {
        SongList(songs: drafting.draft.songs(matching: browser.searchText).reversed()) {
            ListColumns(Self.columns) {
                ColumnLabel("Title").listColumn(.title)
                ColumnLabel("Album").listColumn(.detail)
                ColumnLabel(SongStat.plays.title).listColumn(SongStat.plays.column)
                ColumnLabel("Time").listColumn(.time)
            }
        } row: { item in
            SongRow(item, stat: .plays, columns: Self.columns) {
                SongArtwork(song: item.song, size: ArtworkSize.songRow).listColumn(.artwork)
                SongTitles(item, subtitle: item.song.artist).listColumn(.title)
                RowDetail(item.song.albumTitle).listColumn(.detail)
                RowStat(.plays, of: item.song).listColumn(SongStat.plays.column)
                RowDuration(item.song.duration).listColumn(.time)
                PickToggle(item).listColumn(.accessory)
            }
        }
        .overlay {
            if drafting.draft.isEmpty {
                EmptyState("No picks yet", message: "Add songs from your library, or let Autofill pick for you.") {
                    EmptyStateSymbol("checkmark.circle")
                } actions: {
                    Button("Autofill") { Task { await drafting.autofill() } }
                        .disabled(!drafting.canAutofill)
                }
            }
        }
    }
}
