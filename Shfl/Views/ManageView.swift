import SwiftUI

struct ManageView: View {
    var player: ShufflePlayer
    let onAddTapped: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                if player.allSongs.isEmpty {
                    emptyState
                } else {
                    songList
                }
            }
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", action: onDismiss)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        onAddTapped()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(player.remainingCapacity == 0)
                }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Songs", systemImage: "music.note")
        } description: {
            Text("Add songs from your Apple Music library to start shuffling")
        } actions: {
            Button("Add Songs", action: onAddTapped)
                .buttonStyle(.borderedProminent)
        }
    }

    private var songList: some View {
        List {
            Section {
                ForEach(player.allSongs) { song in
                    SongDisplay(song: song)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                player.removeSong(id: song.id)
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                }
            } header: {
                Text("\(player.songCount) of \(player.capacity) songs")
            }
        }
    }
}
