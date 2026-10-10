import Foundation

// PR 4 → package
/// Autofills from the user's library, fetching a full draft's worth of songs
/// ahead of time so pressing play on an empty draft needn't wait for the
/// library.
///
/// A warmed batch serves one autofill, and only while the autofill algorithm
/// it was fetched with is still the chosen one. Otherwise the fetch is live.
@MainActor
public final class WarmedLibraryAutofillSource: WarmableAutofillSource {
    deinit {} // Keep nonisolated: Xcode 27 synthesizes an isolated one that can crash on release. See ViewTeardownTests.

    private struct Batch {
        let algorithm: AutofillAlgorithm
        let songs: Task<[Song]?, Never>
    }

    private let libraryCatalog: LibraryCatalog
    private let currentAlgorithm: () -> AutofillAlgorithm
    private let batchSize: Int
    private var batch: Batch?

    /// - Parameter algorithm: The chosen autofill algorithm, read at each warm
    ///   and fetch so a settings change takes effect.
    public init(
        libraryCatalog: LibraryCatalog,
        algorithm: @escaping () -> AutofillAlgorithm,
        batchSize: Int = SessionDraft.maxSongs
    ) {
        self.libraryCatalog = libraryCatalog
        self.currentAlgorithm = algorithm
        self.batchSize = batchSize
    }

    public func warm() {
        let algorithm = currentAlgorithm()
        guard batch?.algorithm != algorithm else { return }
        batch?.songs.cancel()
        let source = LibraryAutofillSource(libraryCatalog: libraryCatalog, algorithm: algorithm)
        let limit = batchSize
        batch = Batch(
            algorithm: algorithm,
            // A failed warm leaves the next autofill to fetch live.
            songs: Task { try? await source.fetchSongs(excluding: [], limit: limit) }
        )
    }

    public func fetchSongs(excluding: Set<String>, limit: Int) async throws -> [Song] {
        let algorithm = currentAlgorithm()
        if let batch {
            self.batch = nil
            if batch.algorithm == algorithm, let songs = await batch.songs.value {
                let available = songs.filter { !excluding.contains($0.id) }
                // A batch shorter than asked for already holds the whole library.
                if available.count >= limit || songs.count < batchSize {
                    return Array(available.prefix(limit))
                }
            } else {
                batch.songs.cancel()
            }
        }
        return try await LibraryAutofillSource(libraryCatalog: libraryCatalog, algorithm: algorithm)
            .fetchSongs(excluding: excluding, limit: limit)
    }
}
