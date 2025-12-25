import SwiftUI

struct ManageView: View {
    @ObservedObject var player: ShufflePlayer
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
            .navigationTitle("Your Songs")
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
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 44, height: 44)
                            .overlay {
                                if let url = song.artworkURL {
                                    AsyncImage(url: url) { image in
                                        image.resizable().aspectRatio(contentMode: .fill)
                                    } placeholder: {
                                        Image(systemName: "music.note")
                                            .foregroundStyle(.gray)
                                    }
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                } else {
                                    Image(systemName: "music.note")
                                        .foregroundStyle(.gray)
                                }
                            }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(song.title)
                                .font(.system(size: 16, weight: .medium))
                                .lineLimit(1)

                            Text(song.artist)
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
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
