import Foundation
import SwiftData

nonisolated struct PersistedPlaybackSnapshot: Equatable, Sendable {
    let currentSongId: String?
    let playbackPosition: Double
    let wasPlaying: Bool
    let savedAt: Date
    let queueOrder: [String]
    let playedSongIds: Set<String>

    init(model: PersistedPlaybackState) {
        self.currentSongId = model.currentSongId
        self.playbackPosition = model.playbackPosition
        self.wasPlaying = model.wasPlaying
        self.savedAt = model.savedAt
        self.queueOrder = model.queueOrder
        self.playedSongIds = model.playedSongIds
    }
}

@MainActor
final class PlaybackStateRepository {
    private let modelContext: ModelContext
    private let container: ModelContainer
    private let saveHandler: () throws -> Void

    /// Number of days after which saved state is considered stale
    private static let staleThresholdDays: Int = 7

    init(
        modelContext: ModelContext,
        saveHandler: (() throws -> Void)? = nil
    ) {
        self.modelContext = modelContext
        self.container = modelContext.container
        self.saveHandler = saveHandler ?? { try modelContext.save() }
    }

    /// Loads playback state on a background thread to avoid blocking the main thread during startup.
    nonisolated func loadPlaybackStateAsync() async throws -> PersistedPlaybackSnapshot? {
        let container = self.container
        return try await Task.detached {
            let context = ModelContext(container)
            let descriptor = FetchDescriptor<PersistedPlaybackState>(
                sortBy: [SortDescriptor(\.savedAt, order: .reverse)]
            )
            let states = try context.fetch(descriptor)
            guard let latest = states.first else { return nil }
            return PersistedPlaybackSnapshot(model: latest)
        }.value
    }

    /// Saves the playback state atomically (deletes old, inserts new).
    func savePlaybackState(_ state: PersistedPlaybackState) throws {
        do {
            let descriptor = FetchDescriptor<PersistedPlaybackState>()
            let existingStates = try modelContext.fetch(descriptor)
            for existingState in existingStates {
                modelContext.delete(existingState)
            }

            modelContext.insert(state)
            try saveHandler()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    /// Clears all persisted playback state.
    func clearPlaybackState() throws {
        do {
            let descriptor = FetchDescriptor<PersistedPlaybackState>()
            let existingStates = try modelContext.fetch(descriptor)
            for existingState in existingStates {
                modelContext.delete(existingState)
            }
            try saveHandler()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    /// Checks if the given state is older than the stale threshold.
    func isStateStale(_ state: PersistedPlaybackSnapshot) -> Bool {
        let calendar = Calendar.current
        guard let staleDate = calendar.date(
            byAdding: .day,
            value: -Self.staleThresholdDays,
            to: Date()
        ) else {
            return true
        }
        return state.savedAt < staleDate
    }
}
