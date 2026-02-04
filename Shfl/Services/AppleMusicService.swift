import Combine
import Foundation
import MusicKit

final class AppleMusicService: MusicService, @unchecked Sendable {
    private let player = ApplicationMusicPlayer.shared
    private var stateObservationTask: Task<Void, Never>?
    private var continuation: AsyncStream<PlaybackState>.Continuation?

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

    var currentSongId: String? {
        guard let entry = player.queue.currentEntry,
              case .song(let song) = entry.item else {
            return nil
        }
        return song.id.rawValue
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

    func fetchLibrarySongs(
        sortedBy: SortOption,
        limit: Int,
        offset: Int
    ) async throws -> LibraryPage {
        var request = MusicLibraryRequest<MusicKit.Song>()
        request.limit = limit
        request.offset = offset

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

        let songs = response.items.map { musicKitSong in
            Song(
                id: musicKitSong.id.rawValue,
                title: musicKitSong.title,
                artist: musicKitSong.artistName,
                albumTitle: musicKitSong.albumTitle ?? "",
                artworkURL: nil,
                playCount: musicKitSong.playCount ?? 0,
                lastPlayedDate: musicKitSong.lastPlayedDate
            )
        }

        // hasMore is true if we got a full page (might be more)
        let hasMore = response.items.count == limit

        return LibraryPage(songs: songs, hasMore: hasMore)
    }

    func searchLibrarySongs(query: String, limit: Int, offset: Int) async throws -> LibraryPage {
        // Note: MusicLibrarySearchRequest doesn't support offset-based pagination.
        // We fetch with a higher limit and slice the results to simulate offset.
        // This is a workaround since MusicKit's nextBatch() requires storing the collection.
        var request = MusicLibrarySearchRequest(term: query, types: [MusicKit.Song.self])
        request.limit = offset + limit

        let response = try await request.response()

        let allSongs = response.songs.map { musicKitSong in
            Song(
                id: musicKitSong.id.rawValue,
                title: musicKitSong.title,
                artist: musicKitSong.artistName,
                albumTitle: musicKitSong.albumTitle ?? "",
                artworkURL: nil,
                playCount: musicKitSong.playCount ?? 0,
                lastPlayedDate: musicKitSong.lastPlayedDate
            )
        }

        // Slice to get only the requested page
        let startIndex = min(offset, allSongs.count)
        let endIndex = min(offset + limit, allSongs.count)
        let songs = Array(allSongs[startIndex..<endIndex])

        // hasMore if we got a full page (same logic as browse pagination)
        let hasMore = songs.count == limit

        return LibraryPage(songs: songs, hasMore: hasMore)
    }

    func setQueue(songs: [Song]) async throws {
        print("🎵 setQueue() called with \(songs.count) songs")
        print("🎵 Song IDs requested: \(songs.map { "\($0.title): \($0.id)" })")
        let ids = songs.map { MusicItemID($0.id) }

        // Use MusicLibraryRequest instead of MusicCatalogResourceRequest
        var request = MusicLibraryRequest<MusicKit.Song>()
        request.filter(matching: \.id, memberOf: ids)
        print("🎵 Fetching songs from library...")
        let response = try await request.response()
        print("🎵 Got \(response.items.count) songs from library")
        print("🎵 Song IDs found: \(response.items.map { "\($0.title): \($0.id.rawValue)" } )")

        guard !response.items.isEmpty else {
            print("🎵 No songs found, returning")
            return
        }

        // Reorder response items to match our desired order
        let itemsById = Dictionary(uniqueKeysWithValues: response.items.map { ($0.id.rawValue, $0) })
        let orderedItems = songs.compactMap { itemsById[$0.id] }

        // Log any missing songs
        let missingSongs = songs.filter { itemsById[$0.id] == nil }
        if !missingSongs.isEmpty {
            print("⚠️ WARNING: \(missingSongs.count) songs NOT found in library:")
            for song in missingSongs {
                print("⚠️   - \(song.title) by \(song.artist) (ID: \(song.id))")
            }
        }

        // Start from the first item in our ordered queue
        let queue = ApplicationMusicPlayer.Queue(for: orderedItems, startingAt: orderedItems.first)
        player.queue = queue
        player.state.shuffleMode = .off  // We handle shuffling ourselves
        print("🎵 setQueue() completed with \(orderedItems.count) items, starting at \(orderedItems.first?.title ?? "nil")")
    }

    func insertIntoQueue(songs: [Song]) async throws {
        guard !songs.isEmpty else { return }
        print("🎵 insertIntoQueue() called with \(songs.count) songs: \(songs.map { $0.title })")

        let ids = songs.map { MusicItemID($0.id) }

        var request = MusicLibraryRequest<MusicKit.Song>()
        request.filter(matching: \.id, memberOf: ids)
        let response = try await request.response()

        guard !response.items.isEmpty else {
            print("🎵 No songs found to insert - requested IDs: \(songs.map { $0.id })")
            return
        }

        // Reorder to match our desired order
        let itemsById = Dictionary(uniqueKeysWithValues: response.items.map { ($0.id.rawValue, $0) })
        let orderedItems = songs.compactMap { itemsById[$0.id] }

        // Log any missing songs
        let missingSongs = songs.filter { itemsById[$0.id] == nil }
        if !missingSongs.isEmpty {
            print("⚠️ WARNING: \(missingSongs.count) songs NOT found for insert:")
            for song in missingSongs {
                print("⚠️   - \(song.title) by \(song.artist) (ID: \(song.id))")
            }
        }

        // Insert all songs at once to avoid flooding MusicKit with individual requests
        // MusicKit's insert() accepts MusicItemCollection
        print("🎵 Inserting \(orderedItems.count) items at queue tail...")
        try await player.queue.insert(MusicItemCollection(orderedItems), position: .tail)
        print("🎵 insertIntoQueue() completed - inserted \(orderedItems.count) items")
    }

    func replaceUpcomingQueue(with songs: [Song], currentSong: Song) async throws {
        print("🎵 replaceUpcomingQueue() called with \(songs.count) upcoming songs")

        // Save current playback position and state
        let savedPlaybackTime = player.playbackTime
        let wasPlaying = player.state.playbackStatus == .playing
        print("🎵 Saving playback time: \(savedPlaybackTime), wasPlaying: \(wasPlaying)")

        // Pause first to avoid audible skip
        if wasPlaying {
            player.pause()
        }

        // Build full queue: current song + upcoming songs
        let allSongs = [currentSong] + songs
        let ids = allSongs.map { MusicItemID($0.id) }

        var request = MusicLibraryRequest<MusicKit.Song>()
        request.filter(matching: \.id, memberOf: ids)
        let response = try await request.response()

        guard !response.items.isEmpty else {
            print("🎵 No songs found, returning")
            return
        }

        // Reorder response items to match our desired order
        let itemsById = Dictionary(uniqueKeysWithValues: response.items.map { ($0.id.rawValue, $0) })
        let orderedItems = allSongs.compactMap { itemsById[$0.id] }

        // Set the new queue starting from the current song
        let queue = ApplicationMusicPlayer.Queue(for: orderedItems, startingAt: orderedItems.first)
        player.queue = queue
        player.state.shuffleMode = .off

        // Resume playback if it was playing, then seek
        if wasPlaying {
            try await player.play()
            // Seek AFTER play() - setting before gets ignored
            player.playbackTime = savedPlaybackTime
            print("🎵 Resumed playback at \(savedPlaybackTime)")
        } else {
            player.playbackTime = savedPlaybackTime
            print("🎵 Queue updated at \(savedPlaybackTime) (paused)")
        }

        print("🎵 replaceUpcomingQueue() completed with \(orderedItems.count) items")
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

    func seek(to time: TimeInterval) {
        print("⏩ seek(to: \(time)) called")
        player.playbackTime = max(0, time)
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
            artworkURL: musicKitSong.artwork?.url(width: 1200, height: 1200),
            playCount: musicKitSong.playCount ?? 0,
            lastPlayedDate: musicKitSong.lastPlayedDate
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
