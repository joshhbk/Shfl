import SwiftUI

struct SongPickerView: View {
    @ObservedObject var player: ShufflePlayer
    let musicService: MusicService
    let onDismiss: () -> Void

    @State private var searchText = ""
    @State private var searchResults: [Song] = []
    @State private var isSearching = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                capacityBar

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

    private var capacityBar: some View {
        HStack {
            Text("\(player.songCount) of \(player.capacity) songs")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            Spacer()

            if player.remainingCapacity == 0 {
                Text("Full")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.systemGroupedBackground))
    }

    private var songList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(searchResults) { song in
                    SongRow(
                        song: song,
                        isSelected: player.containsSong(id: song.id),
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
        } else {
            do {
                try player.addSong(song)
            } catch ShufflePlayerError.capacityReached {
                errorMessage = "You've reached the maximum of \(player.capacity) songs"
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
