import Foundation
import SwiftData

/// The cross-launch session read back from storage.
nonisolated struct ArchivedSession: Equatable, Sendable {
    let pool: [Song]
    let session: ListeningSessionRecord?

    static let empty = ArchivedSession(pool: [], session: nil)
}

enum SessionArchiveError: Error {
    case encodingFailed
}

/// The single persistence module for the song pool and the active listening
/// session. Hides SwiftData, JSON encoding, and atomic replacement behind one
/// three-method interface.
@MainActor
final class SessionArchive {
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

    /// Loads on a background context to avoid blocking the main thread at launch.
    nonisolated func loadAsync() async throws -> ArchivedSession {
        let container = self.container
        return try await Task.detached {
            let context = ModelContext(container)
            let descriptor = FetchDescriptor<PersistedSession>(
                sortBy: [SortDescriptor(\.savedAt, order: .reverse)]
            )
            guard let latest = try context.fetch(descriptor).first else {
                return .empty
            }
            return try Self.decode(latest)
        }.value
    }

    func load() throws -> ArchivedSession {
        let descriptor = FetchDescriptor<PersistedSession>(
            sortBy: [SortDescriptor(\.savedAt, order: .reverse)]
        )
        guard let latest = try modelContext.fetch(descriptor).first else {
            return .empty
        }
        return try Self.decode(latest)
    }

    /// Atomically replaces the stored session. The pool and the active session
    /// are written together, so they can never disagree.
    func commit(pool: [Song], session: ListeningSessionRecord?) throws {
        do {
            let descriptor = FetchDescriptor<PersistedSession>()
            for existing in try modelContext.fetch(descriptor) {
                modelContext.delete(existing)
            }

            let record = PersistedSession(
                savedAt: session?.savedAt ?? Date(),
                poolJSON: try Self.encode(pool),
                sessionJSON: try session.map(Self.encode)
            )
            modelContext.insert(record)
            try saveHandler()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    /// Clears the active session but keeps the song pool.
    func clearActiveSession() throws {
        let pool = try load().pool
        try commit(pool: pool, session: nil)
    }

    func clearAll() throws {
        do {
            let descriptor = FetchDescriptor<PersistedSession>()
            for existing in try modelContext.fetch(descriptor) {
                modelContext.delete(existing)
            }
            try saveHandler()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private nonisolated static func decode(_ model: PersistedSession) throws -> ArchivedSession {
        let pool = try decode([Song].self, from: model.poolJSON)
        let session = try model.sessionJSON.map {
            try decode(ListeningSessionRecord.self, from: $0)
        }
        return ArchivedSession(pool: pool, session: session)
    }

    private nonisolated static func encode<T: Encodable>(_ value: T) throws -> String {
        let data = try JSONEncoder().encode(value)
        guard let json = String(data: data, encoding: .utf8) else {
            throw SessionArchiveError.encodingFailed
        }
        return json
    }

    private nonisolated static func decode<T: Decodable>(_ type: T.Type, from json: String) throws -> T {
        guard let data = json.data(using: .utf8) else {
            throw SessionArchiveError.encodingFailed
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}