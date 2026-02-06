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

    enum ArtworkType {
        case song
        case artist
        case playlist
    }

    private var cache: [String: Artwork] = [:]
    private var pending: Set<String> = []
    private var loadQueue: [(id: String, type: ArtworkType)] = []
    private var isProcessing = false

    private init() {}

    func artwork(for songId: String) -> Artwork? {
        cache[songId]
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
            for song in response.items {
                let songId = song.id.rawValue
                if let artwork = song.artwork {
                    cache[songId] = artwork
                    NotificationCenter.default.post(
                        name: Self.artworkDidLoad,
                        object: nil,
                        userInfo: ["songId": songId]
                    )
                }
                pending.remove(songId)
            }
        } catch {
            for id in songIds {
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
            for artist in response.items {
                let artistId = artist.id.rawValue
                if let artwork = artist.artwork {
                    cache[artistId] = artwork
                    NotificationCenter.default.post(
                        name: Self.artworkDidLoad,
                        object: nil,
                        userInfo: ["songId": artistId]
                    )
                }
                pending.remove(artistId)
            }
        } catch {
            for id in artistIds {
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
            for playlist in response.items {
                let playlistId = playlist.id.rawValue
                if let artwork = playlist.artwork {
                    cache[playlistId] = artwork
                    NotificationCenter.default.post(
                        name: Self.artworkDidLoad,
                        object: nil,
                        userInfo: ["songId": playlistId]
                    )
                }
                pending.remove(playlistId)
            }
        } catch {
            for id in playlistIds {
                pending.remove(id)
            }
        }
    }
}
