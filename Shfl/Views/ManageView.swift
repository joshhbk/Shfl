import SwiftUI

struct ManageView: View {
    var player: ShufflePlayer
    let onAddTapped: () -> Void
    let onDismiss: () -> Void
    @Environment(\.sessionDraft) private var sessionDraft
    @Environment(\.listeningSessionHost) private var sessionHost

    var body: some View {
        NavigationStack {
            Group {
                if sessionDraft.isEmpty {
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
                    .disabled(sessionDraft.isAtCapacity)
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
            if player.activeSession != nil {
                Section {
                    Label(
                        "Changes here apply to your next shuffle. Current playback keeps its order.",
                        systemImage: "forward.end"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                    if player.hasPendingSessionChanges, !sessionDraft.isEmpty {
                        Button {
                            Task { await sessionHost?.startFreshShuffle() }
                        } label: {
                            if sessionHost?.isStartingSession == true {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                            } else {
                                Text("Start New Shuffle Now")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .disabled(sessionHost?.isStartingSession ?? true)
                    }
                }
            }

            Section {
                ForEach(sessionDraft.songs) { song in
                    SongDisplay(song: song)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                sessionDraft.remove(songID: song.id)
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                }
            } header: {
                Text("\(sessionDraft.songCount) of \(sessionDraft.capacity) songs")
            }
        }
    }
}
