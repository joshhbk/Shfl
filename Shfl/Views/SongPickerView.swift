import SwiftUI

struct SongPickerView: View {
    @ObservedObject var player: ShufflePlayer
    let musicService: MusicService
    let onDismiss: () -> Void

    @State private var searchText = ""
    @State private var searchResults: [Song] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @StateObject private var undoManager = SongUndoManager()

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    CapacityProgressBar(current: player.songCount, maximum: player.capacity)

                    if isSearching {
                        ProgressView("Searching...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if searchResults.isEmpty && !searchText.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                    } else if searchResults.isEmpty {
                        ContentUnavailableView(
                            "Search Your Library",
                            systemImage: "magnifyingglass",
                            description: Text("Type to search your Apple Music library")
                        )
                    } else {
                        songList
                    }
                }

                // Undo pill overlay
                if let undoState = undoManager.currentState {
                    UndoPill(
                        state: undoState,
                        onUndo: { handleUndo(undoState) },
                        onDismiss: { undoManager.dismiss() }
                    )
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Add Songs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDismiss)
                }
            }
            .searchable(text: $searchText, prompt: "Search your library")
            .onChange(of: searchText) { _, newValue in
                performSearch(query: newValue)
            }
            .alert("Error", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                if let error = errorMessage {
                    Text(error)
                }
            }
        }
    }

    private var songList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(searchResults) { song in
                    SongRow(
                        song: song,
                        isSelected: player.containsSong(id: song.id),
                        isAtCapacity: player.remainingCapacity == 0,
                        onToggle: { toggleSong(song) }
                    )
                    Divider()
                        .padding(.leading, 72)
                }
            }
        }
    }

    private func performSearch(query: String) {
        guard !query.isEmpty else {
            searchResults = []
            return
        }

        isSearching = true
        Task {
            do {
                let results = try await musicService.searchLibrary(query: query)
                await MainActor.run {
                    searchResults = results
                    isSearching = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isSearching = false
                }
            }
        }
    }

    private func toggleSong(_ song: Song) {
        if player.containsSong(id: song.id) {
            player.removeSong(id: song.id)
            undoManager.recordAction(.removed, song: song)
        } else {
            do {
                try player.addSong(song)
                undoManager.recordAction(.added, song: song)

                // Check for milestones
                if CapacityProgressBar.isMilestone(player.songCount) {
                    HapticFeedback.milestone.trigger()
                }
            } catch ShufflePlayerError.capacityReached {
                // Handled by SongRow's nope animation
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func handleUndo(_ state: UndoState) {
        switch state.action {
        case .added:
            // Undo add = remove
            player.removeSong(id: state.song.id)
            HapticFeedback.light.trigger()
        case .removed:
            // Undo remove = add back
            try? player.addSong(state.song)
            HapticFeedback.medium.trigger()
        }
        undoManager.dismiss()
    }
}
