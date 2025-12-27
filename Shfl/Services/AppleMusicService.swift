import Combine
import Foundation
import MusicKit

final class AppleMusicService: MusicService, @unchecked Sendable {
    private let player = ApplicationMusicPlayer.shared
    private var stateObservationTask: Task<Void, Never>?
    private var continuation: AsyncStream<PlaybackState>.Continuation?

    // Library cache
    private var cachedLibrary: [SortOption: [Song]] = [:]
    private var prefetchTask: Task<Void, Never>?

    var playbackStateStream: AsyncStream<PlaybackState> {
        AsyncStream { [weak self] continuation in
            self?.continuation = continuation
            self?.startObservingPlaybackState()
        }
    }

    var isAuthorized: Bool {
        get async {
            MusicAuthorization.currentStatus == .authorized
        }
    }

    func requestAuthorization() async -> Bool {
        let status = await MusicAuthorization.request()
        return status == .authorized
    }

    /// Prefetch library songs in background for faster access later
    func prefetchLibrary() async {
        // Prefetch most common sort option
        _ = try? await fetchAllLibrarySongs(sortedBy: .mostPlayed)
    }

    private func fetchAllLibrarySongs(sortedBy: SortOption) async throws -> [Song] {
        // Return cached if available
        if let cached = cachedLibrary[sortedBy] {
            return cached
        }

        var request = MusicLibraryRequest<MusicKit.Song>()

        switch sortedBy {
        case .mostPlayed:
            request.sort(by: \.playCount, ascending: false)
        case .recentlyPlayed:
            request.sort(by: \.lastPlayedDate, ascending: false)
        case .recentlyAdded:
            request.sort(by: \.libraryAddedDate, ascending: false)
        case .alphabetical:
            request.sort(by: \.title, ascending: true)
        }

        let response = try await request.response()

        // Map songs and try to get artwork (preserving order)
        let allSongs = await withTaskGroup(of: (Int, Song).self, returning: [Song].self) { group in
            for (index, musicKitSong) in response.items.enumerated() {
                group.addTask {
                    // Try to load artwork by requesting full song data
                    var artworkURL: URL?
                    if let artwork = musicKitSong.artwork {
                        artworkURL = artwork.url(width: 300, height: 300)
                    } else {
                        // Artwork is nil, try to fetch full song
                        if let fullSong = try? await musicKitSong.with(.albums) {
                            artworkURL = fullSong.artwork?.url(width: 300, height: 300)
                        }
                    }

                    let song = Song(
                        id: musicKitSong.id.rawValue,
                        title: musicKitSong.title,
                        artist: musicKitSong.artistName,
                        albumTitle: musicKitSong.albumTitle ?? "",
                        artworkURL: artworkURL
                    )
                    return (index, song)
                }
            }

            var indexedSongs: [(Int, Song)] = []
            for await result in group {
                indexedSongs.append(result)
            }
            // Sort by original index to preserve order
            return indexedSongs.sorted { $0.0 < $1.0 }.map { $0.1 }
        }

        // Cache the result
        cachedLibrary[sortedBy] = allSongs
        return allSongs
    }

    func fetchLibrarySongs(
        sortedBy: SortOption,
        limit: Int,
        offset: Int
    ) async throws -> LibraryPage {
        let allSongs = try await fetchAllLibrarySongs(sortedBy: sortedBy)

        let startIndex = min(offset, allSongs.count)
        let endIndex = min(offset + limit, allSongs.count)
        let pageItems = Array(allSongs[startIndex..<endIndex])
        let hasMore = endIndex < allSongs.count

        return LibraryPage(songs: pageItems, hasMore: hasMore)
    }

    func searchLibrarySongs(query: String) async throws -> [Song] {
        var request = MusicLibrarySearchRequest(term: query, types: [MusicKit.Song.self])
        let response = try await request.response()

        return response.songs.map { musicKitSong in
            Song(
                id: musicKitSong.id.rawValue,
                title: musicKitSong.title,
                artist: musicKitSong.artistName,
                albumTitle: musicKitSong.albumTitle ?? "",
                artworkURL: musicKitSong.artwork?.url(width: 300, height: 300)
            )
        }
    }

    func setQueue(songs: [Song]) async throws {
        let ids = songs.map { MusicItemID($0.id) }

        // Use MusicLibraryRequest instead of MusicCatalogResourceRequest
        var request = MusicLibraryRequest<MusicKit.Song>()
        request.filter(matching: \.id, memberOf: ids)
        let response = try await request.response()

        guard !response.items.isEmpty else {
            return
        }

        let queue = ApplicationMusicPlayer.Queue(for: response.items, startingAt: nil)
        player.queue = queue
        player.state.shuffleMode = .songs
    }

    func play() async throws {
        try await player.play()
    }

    func pause() async {
        player.pause()
    }

    func skipToNext() async throws {
        try await player.skipToNextEntry()
    }

    private func startObservingPlaybackState() {
        stateObservationTask?.cancel()
        stateObservationTask = Task { [weak self] in
            guard let self else { return }

            // Initial state
            self.emitCurrentState()

            // Observe state changes
            for await _ in self.player.state.objectWillChange.values {
                self.emitCurrentState()
            }
        }
    }

    private func emitCurrentState() {
        let state = mapPlaybackState()
        continuation?.yield(state)
    }

    private func mapPlaybackState() -> PlaybackState {
        guard let currentEntry = player.queue.currentEntry else {
            return .empty
        }

        guard case .song(let musicKitSong) = currentEntry.item else {
            return .stopped
        }

        let song = Song(
            id: musicKitSong.id.rawValue,
            title: musicKitSong.title,
            artist: musicKitSong.artistName,
            albumTitle: musicKitSong.albumTitle ?? "",
            artworkURL: musicKitSong.artwork?.url(width: 300, height: 300)
        )

        switch player.state.playbackStatus {
        case .playing:
            return .playing(song)
        case .paused:
            return .paused(song)
        case .stopped:
            return .stopped
        case .interrupted:
            return .paused(song)
        case .seekingForward, .seekingBackward:
            return .playing(song)
        @unknown default:
            return .stopped
        }
    }
}
