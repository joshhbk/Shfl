import MusicKit
import SwiftUI

/// Lazy artwork loader with rate limiting to avoid overwhelming MusicKit
@Observable
@MainActor
final class ArtworkLoader {
    static let shared = ArtworkLoader()

    @ObservationIgnored private var cache: [String: Artwork] = [:]
    @ObservationIgnored private var pending: Set<String> = []
    @ObservationIgnored private var loadQueue: [String] = []
    @ObservationIgnored private var isProcessing = false

    /// Triggers view updates when artwork is loaded
    private(set) var lastUpdateTimestamp = Date()

    private init() {}

    func artwork(for songId: String) -> Artwork? {
        cache[songId]
    }

    func requestArtwork(for songId: String) {
        // Already cached or pending
        guard cache[songId] == nil, !pending.contains(songId) else { return }

        pending.insert(songId)
        loadQueue.append(songId)
        processQueue()
    }

    private func processQueue() {
        guard !isProcessing, !loadQueue.isEmpty else { return }

        isProcessing = true

        Task {
            // Process in small batches with delays
            while !loadQueue.isEmpty {
                let batch = Array(loadQueue.prefix(5))
                loadQueue.removeFirst(min(5, loadQueue.count))

                await loadBatch(batch)

                // Small delay between batches to avoid overwhelming MusicKit
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }
            isProcessing = false
        }
    }

    private func loadBatch(_ songIds: [String]) async {
        let ids = songIds.map { MusicItemID($0) }

        var request = MusicLibraryRequest<MusicKit.Song>()
        request.filter(matching: \.id, memberOf: ids)

        do {
            let response = try await request.response()
            for song in response.items {
                if let artwork = song.artwork {
                    cache[song.id.rawValue] = artwork
                }
                pending.remove(song.id.rawValue)
            }
            // Trigger UI update
            lastUpdateTimestamp = Date()
        } catch {
            // Remove from pending on error so they can retry
            for id in songIds {
                pending.remove(id)
            }
        }
    }
}
