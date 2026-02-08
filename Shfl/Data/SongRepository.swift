import Foundation
import SwiftData

@MainActor
final class SongRepository {
    private let modelContext: ModelContext
    private let container: ModelContainer
    private let saveHandler: () throws -> Void

    init(
        modelContext: ModelContext,
        saveHandler: (() throws -> Void)? = nil
    ) {
        self.modelContext = modelContext
        self.container = modelContext.container
        self.saveHandler = saveHandler ?? { try modelContext.save() }
    }

    /// Loads songs on a background thread to avoid blocking the main thread during startup.
    nonisolated func loadSongsAsync() async throws -> [Song] {
        let container = self.container
        return try await Task.detached {
            let context = ModelContext(container)
            let descriptor = FetchDescriptor<PersistedSong>(
                sortBy: [SortDescriptor(\.orderIndex)]
            )
            let persisted = try context.fetch(descriptor)
            return persisted.map { $0.toSong() }
        }.value
    }

    func saveSongs(_ songs: [Song]) throws {
        do {
            // Replace snapshot in-memory first, then commit once.
            let descriptor = FetchDescriptor<PersistedSong>()
            let existing = try modelContext.fetch(descriptor)
            for song in existing {
                modelContext.delete(song)
            }

            for (index, song) in songs.enumerated() {
                let persisted = PersistedSong.from(song, orderIndex: index)
                modelContext.insert(persisted)
            }

            try saveHandler()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    func loadSongs() throws -> [Song] {
        let descriptor = FetchDescriptor<PersistedSong>(
            sortBy: [SortDescriptor(\.orderIndex)]
        )
        let persisted = try modelContext.fetch(descriptor)
        return persisted.map { $0.toSong() }
    }

    func clearSongs() throws {
        do {
            let descriptor = FetchDescriptor<PersistedSong>()
            let existing = try modelContext.fetch(descriptor)
            for song in existing {
                modelContext.delete(song)
            }
            try saveHandler()
        } catch {
            modelContext.rollback()
            throw error
        }
    }
}
