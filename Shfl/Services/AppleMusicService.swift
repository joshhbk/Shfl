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

    var currentPlaybackTime: TimeInterval {
        player.playbackTime
    }

    var currentSongDuration: TimeInterval {
        guard let entry = player.queue.currentEntry,
              case .song(let song) = entry.item,
              let duration = song.duration else {
            return 0
        }
        return duration
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
            print("📚 Returning \(cached.count) cached songs for \(sortedBy)")
            return cached
        }

        print("📚 Fetching library songs for \(sortedBy)...")
        var request = MusicLibraryRequest<MusicKit.Song>()

        // Limit for faster loading during development
        request.limit = 1000

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
        print("📚 Got \(response.items.count) songs from MusicKit")

        // Map songs (artwork loaded lazily by ArtworkLoader)
        let allSongs = response.items.map { musicKitSong in
            Song(
                id: musicKitSong.id.rawValue,
                title: musicKitSong.title,
                artist: musicKitSong.artistName,
                albumTitle: musicKitSong.albumTitle ?? "",
                artworkURL: nil
            )
        }

        // Only cache if we got results
        if !allSongs.isEmpty {
            cachedLibrary[sortedBy] = allSongs
        }
        print("📚 Processed \(allSongs.count) songs")
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
        print("🔍 Searching for: '\(query)'")

        // Search directly against cached library - no async fetch needed
        guard let allSongs = cachedLibrary[.mostPlayed] else {
            print("🔍 Cache miss - no songs cached yet")
            return []
        }

        let lowercasedQuery = query.lowercased()
        let results = allSongs.filter { song in
            song.title.lowercased().contains(lowercasedQuery) ||
            song.artist.lowercased().contains(lowercasedQuery) ||
            song.albumTitle.lowercased().contains(lowercasedQuery)
        }

        print("🔍 Found \(results.count) results for '\(query)'")
        return results
    }

    func setQueue(songs: [Song]) async throws {
        print("🎵 setQueue() called with \(songs.count) songs")
        let ids = songs.map { MusicItemID($0.id) }

        // Use MusicLibraryRequest instead of MusicCatalogResourceRequest
        var request = MusicLibraryRequest<MusicKit.Song>()
        request.filter(matching: \.id, memberOf: ids)
        print("🎵 Fetching songs from library...")
        let response = try await request.response()
        print("🎵 Got \(response.items.count) songs from library")

        guard !response.items.isEmpty else {
            print("🎵 No songs found, returning")
            return
        }

        let queue = ApplicationMusicPlayer.Queue(for: response.items, startingAt: nil)
        player.queue = queue
        player.state.shuffleMode = .songs
        print("🎵 setQueue() completed")
    }

    func play() async throws {
        print("▶️ play() called")
        try await player.play()
        print("▶️ play() completed")
    }

    func pause() async {
        print("⏸️ pause() called")
        player.pause()
        print("⏸️ pause() completed")
    }

    func skipToNext() async throws {
        print("⏭️ skipToNext() called")
        try await player.skipToNextEntry()
        print("⏭️ skipToNext() completed")
    }

    func skipToPrevious() async throws {
        print("⏮️ skipToPrevious() called")
        try await player.skipToPreviousEntry()
        print("⏮️ skipToPrevious() completed")
    }

    func restartOrSkipToPrevious() async throws {
        let threshold: TimeInterval = 3.0
        print("⏮️ restartOrSkipToPrevious() called - playbackTime: \(player.playbackTime)")

        if player.playbackTime <= threshold {
            try await skipToPrevious()
        } else {
            player.playbackTime = 0
            print("⏮️ Restarted current song")
        }
    }

    private func startObservingPlaybackState() {
        stateObservationTask?.cancel()
        stateObservationTask = Task { [weak self] in
            guard let self else { return }

            // Initial state
            self.emitCurrentState()

            // Observe both state AND queue changes
            // State changes: play/pause/stop status
            // Queue changes: current song advances
            async let stateChanges: Void = {
                for await _ in self.player.state.objectWillChange.values {
                    self.emitCurrentState()
                }
            }()

            async let queueChanges: Void = {
                for await _ in self.player.queue.objectWillChange.values {
                    self.emitCurrentState()
                }
            }()

            // Keep both running
            _ = await (stateChanges, queueChanges)
        }
    }

    private func emitCurrentState() {
        let state = mapPlaybackState()
        print("📻 Emitting state: \(state)")
        continuation?.yield(state)
    }

    private func mapPlaybackState() -> PlaybackState {
        print("📻 Mapping state - playbackStatus: \(player.state.playbackStatus)")
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
