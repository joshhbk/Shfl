import Foundation
import MusicKit

/// Non-observable artwork storage to prevent observation fan-out.
/// Views query this directly; changes are signaled via NotificationCenter
/// so only the specific view for that song updates.
@MainActor
final class ArtworkCache {
    static let shared = ArtworkCache()

    /// Notification posted when a specific song's artwork is loaded.
    /// userInfo contains "songId": String
    static let artworkDidLoad = Notification.Name("ArtworkCacheDidLoad")

    private var cache: [String: Artwork] = [:]
    private var pending: Set<String> = []
    private var loadQueue: [String] = []
    private var isProcessing = false

    private init() {}

    func artwork(for songId: String) -> Artwork? {
        cache[songId]
    }

    func requestArtwork(for songId: String) {
        guard cache[songId] == nil, !pending.contains(songId) else { return }

        pending.insert(songId)
        loadQueue.append(songId)
        processQueue()
    }

    private func processQueue() {
        guard !isProcessing, !loadQueue.isEmpty else { return }

        isProcessing = true

        Task {
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
                let songId = song.id.rawValue
                if let artwork = song.artwork {
                    cache[songId] = artwork
                    // Post notification for this specific song only
                    NotificationCenter.default.post(
                        name: Self.artworkDidLoad,
                        object: nil,
                        userInfo: ["songId": songId]
                    )
                }
                pending.remove(songId)
            }
        } catch {
            // Remove from pending on error so they can retry
            for id in songIds {
                pending.remove(id)
            }
        }
    }
}
