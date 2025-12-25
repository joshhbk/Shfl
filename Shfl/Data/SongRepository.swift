import Foundation
import SwiftData

@MainActor
final class SongRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func saveSongs(_ songs: [Song]) throws {
        // Clear existing
        try clearSongs()

        // Insert new
        for (index, song) in songs.enumerated() {
            let persisted = PersistedSong.from(song, orderIndex: index)
            modelContext.insert(persisted)
        }

        try modelContext.save()
    }

    func loadSongs() throws -> [Song] {
        let descriptor = FetchDescriptor<PersistedSong>(
            sortBy: [SortDescriptor(\.orderIndex)]
        )
        let persisted = try modelContext.fetch(descriptor)
        return persisted.map { $0.toSong() }
    }

    func clearSongs() throws {
        try modelContext.delete(model: PersistedSong.self)
    }
}
