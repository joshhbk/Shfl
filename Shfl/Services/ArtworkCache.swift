import Foundation
import MusicKit

/// Boundary note:
/// - App/domain state propagation uses Observation.
/// - Artwork loading uses targeted AsyncStream updates per entity id.
/// This avoids global observation fan-out for artwork-heavy lists while
/// keeping eventing local and typed (no NotificationCenter payload parsing).
@MainActor
final class ArtworkCache {
    static let shared = ArtworkCache()

    enum ArtworkType {
        case song
        case artist
        case playlist
    }

    private var cache: [String: Artwork] = [:]
    private var pending: Set<String> = []
    private var loadQueue: [(id: String, type: ArtworkType)] = []
    private var isProcessing = false
    private var updateContinuations: [String: [UUID: AsyncStream<Artwork>.Continuation]] = [:]

    private init() {}

#if DEBUG
    static func makeForTesting() -> ArtworkCache {
        ArtworkCache()
    }
#endif

    func artwork(for songId: String) -> Artwork? {
        cache[songId]
    }

    /// Inserts preloaded artwork and publishes an update to listeners for this id.
    /// Useful for deterministic tests and future preload paths.
    func setArtwork(_ artwork: Artwork, for id: String) {
        cache[id] = artwork
        pending.remove(id)
        publishUpdate(for: id, artwork: artwork)
    }

    func requestArtwork(for songId: String) {
        requestArtwork(for: songId, type: .song)
    }

    func requestArtwork(for id: String, type: ArtworkType) {
        guard cache[id] == nil, !pending.contains(id) else { return }

        pending.insert(id)
        loadQueue.append((id: id, type: type))
        processQueue()
    }

    func artworkUpdates(for id: String) -> AsyncStream<Artwork> {
        if let cached = cache[id] {
            return AsyncStream { continuation in
                continuation.yield(cached)
                continuation.finish()
            }
        }

        let token = UUID()
        return AsyncStream { [weak self] continuation in
            guard let self else {
                continuation.finish()
                return
            }

            var waiters = self.updateContinuations[id, default: [:]]
            waiters[token] = continuation
            self.updateContinuations[id] = waiters

            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.removeContinuation(for: id, token: token)
                }
            }
        }
    }

    private func processQueue() {
        guard !isProcessing, !loadQueue.isEmpty else { return }

        isProcessing = true

        Task {
            while !loadQueue.isEmpty {
                let batch = Array(loadQueue.prefix(5))
                loadQueue.removeFirst(min(5, loadQueue.count))

                // Group by type for efficient batching
                let songItems = batch.filter { $0.type == .song }
                let artistItems = batch.filter { $0.type == .artist }
                let playlistItems = batch.filter { $0.type == .playlist }

                if !songItems.isEmpty {
                    await loadSongBatch(songItems.map(\.id))
                }
                if !artistItems.isEmpty {
                    await loadArtistBatch(artistItems.map(\.id))
                }
                if !playlistItems.isEmpty {
                    await loadPlaylistBatch(playlistItems.map(\.id))
                }

                // Small delay between batches to avoid overwhelming MusicKit
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }
            isProcessing = false
        }
    }

    private func loadSongBatch(_ songIds: [String]) async {
        let ids = songIds.map { MusicItemID($0) }

        var request = MusicLibraryRequest<MusicKit.Song>()
        request.filter(matching: \.id, memberOf: ids)

        do {
            let response = try await request.response()
            var loadedIds: Set<String> = []
            for song in response.items {
                let songId = song.id.rawValue
                if let artwork = song.artwork {
                    cache[songId] = artwork
                    publishUpdate(for: songId, artwork: artwork)
                }
                loadedIds.insert(songId)
                pending.remove(songId)
            }

            for id in songIds where !loadedIds.contains(id) {
                finishWaiters(for: id)
                pending.remove(id)
            }
        } catch {
            for id in songIds {
                finishWaiters(for: id)
                pending.remove(id)
            }
        }
    }

    private func loadArtistBatch(_ artistIds: [String]) async {
        let ids = artistIds.map { MusicItemID($0) }

        var request = MusicLibraryRequest<MusicKit.Artist>()
        request.filter(matching: \.id, memberOf: ids)

        do {
            let response = try await request.response()
            var loadedIds: Set<String> = []
            for artist in response.items {
                let artistId = artist.id.rawValue
                if let artwork = artist.artwork {
                    cache[artistId] = artwork
                    publishUpdate(for: artistId, artwork: artwork)
                }
                loadedIds.insert(artistId)
                pending.remove(artistId)
            }

            for id in artistIds where !loadedIds.contains(id) {
                finishWaiters(for: id)
                pending.remove(id)
            }
        } catch {
            for id in artistIds {
                finishWaiters(for: id)
                pending.remove(id)
            }
        }
    }

    private func loadPlaylistBatch(_ playlistIds: [String]) async {
        let ids = playlistIds.map { MusicItemID($0) }

        var request = MusicLibraryRequest<MusicKit.Playlist>()
        request.filter(matching: \.id, memberOf: ids)

        do {
            let response = try await request.response()
            var loadedIds: Set<String> = []
            for playlist in response.items {
                let playlistId = playlist.id.rawValue
                if let artwork = playlist.artwork {
                    cache[playlistId] = artwork
                    publishUpdate(for: playlistId, artwork: artwork)
                }
                loadedIds.insert(playlistId)
                pending.remove(playlistId)
            }

            for id in playlistIds where !loadedIds.contains(id) {
                finishWaiters(for: id)
                pending.remove(id)
            }
        } catch {
            for id in playlistIds {
                finishWaiters(for: id)
                pending.remove(id)
            }
        }
    }

    private func publishUpdate(for id: String, artwork: Artwork) {
        guard let waiters = updateContinuations.removeValue(forKey: id) else { return }
        for continuation in waiters.values {
            continuation.yield(artwork)
            continuation.finish()
        }
    }

    private func finishWaiters(for id: String) {
        guard let waiters = updateContinuations.removeValue(forKey: id) else { return }
        for continuation in waiters.values {
            continuation.finish()
        }
    }

    private func removeContinuation(for id: String, token: UUID) {
        guard var waiters = updateContinuations[id] else { return }
        waiters.removeValue(forKey: token)
        if waiters.isEmpty {
            updateContinuations.removeValue(forKey: id)
        } else {
            updateContinuations[id] = waiters
        }
    }
}
