import Combine
import Foundation
import MusicKit

final class AppleMusicService: MusicService {
    private let player = ApplicationMusicPlayer.shared
    private var stateObservationTask: Task<Void, Never>?
    private let observationTaskLock = NSLock()
    private let playbackStateBroadcaster = PlaybackStateBroadcaster()

    var playbackStateStream: AsyncStream<PlaybackState> {
        let currentState = mapPlaybackState()
        let stream = playbackStateBroadcaster.stream(replaying: currentState)
        startObservingPlaybackStateIfNeeded()
        return stream
    }

    deinit {
        observationTaskLock.lock()
        let task = stateObservationTask
        stateObservationTask = nil
        observationTaskLock.unlock()
        task?.cancel()
        playbackStateBroadcaster.finishAll()
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

    var transportQueueEntryCount: Int { player.queue.entries.count }

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

    func fetchLibraryArtists(limit: Int, offset: Int) async throws -> ArtistPage {
        var request = MusicLibraryRequest<MusicKit.Artist>()
        request.limit = limit
        request.offset = offset
        request.sort(by: \.name, ascending: true)

        let response = try await request.response()

        let artists = response.items.map { musicKitArtist in
            Artist(
                id: musicKitArtist.id.rawValue,
                name: musicKitArtist.name
            )
        }

        let hasMore = response.items.count == limit
        return ArtistPage(artists: artists, hasMore: hasMore)
    }

    func fetchLibraryPlaylists(limit: Int, offset: Int) async throws -> PlaylistPage {
        var request = MusicLibraryRequest<MusicKit.Playlist>()
        request.limit = limit
        request.offset = offset
        request.sort(by: \.name, ascending: true)

        let response = try await request.response()

        let playlists = response.items.map { musicKitPlaylist in
            Playlist(
                id: musicKitPlaylist.id.rawValue,
                name: musicKitPlaylist.name
            )
        }

        let hasMore = response.items.count == limit
        return PlaylistPage(playlists: playlists, hasMore: hasMore)
    }

    func fetchSongs(byArtist artistName: String, limit: Int, offset: Int) async throws -> LibraryPage {
        var request = MusicLibraryRequest<MusicKit.Song>()
        request.limit = limit
        request.offset = offset
        request.filter(matching: \.artistName, equalTo: artistName)
        request.sort(by: \.title, ascending: true)

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

        let hasMore = response.items.count == limit
        return LibraryPage(songs: songs, hasMore: hasMore)
    }

    func fetchSongs(byPlaylistId playlistId: String, limit: Int, offset: Int) async throws -> LibraryPage {
        // Fetch the playlist by ID, then get its tracks
        var request = MusicLibraryRequest<MusicKit.Playlist>()
        request.filter(matching: \.id, equalTo: MusicItemID(playlistId))

        let response = try await request.response()

        guard let playlist = response.items.first else {
            return LibraryPage(songs: [], hasMore: false)
        }

        // Load the playlist's tracks
        let detailedPlaylist = try await playlist.with([.tracks])

        guard let tracks = detailedPlaylist.tracks else {
            return LibraryPage(songs: [], hasMore: false)
        }

        let allSongs = tracks.compactMap { track -> Song? in
            guard case .song(let musicKitSong) = track else { return nil }
            return Song(
                id: musicKitSong.id.rawValue,
                title: musicKitSong.title,
                artist: musicKitSong.artistName,
                albumTitle: musicKitSong.albumTitle ?? "",
                artworkURL: nil,
                playCount: musicKitSong.playCount ?? 0,
                lastPlayedDate: musicKitSong.lastPlayedDate
            )
        }

        // Manual pagination over the track list
        let startIndex = min(offset, allSongs.count)
        let endIndex = min(offset + limit, allSongs.count)
        let songs = Array(allSongs[startIndex..<endIndex])
        let hasMore = endIndex < allSongs.count

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

    func searchLibraryArtists(query: String, limit: Int, offset: Int) async throws -> ArtistPage {
        var request = MusicLibrarySearchRequest(term: query, types: [MusicKit.Artist.self])
        request.limit = offset + limit

        let response = try await request.response()

        let allArtists = response.artists.map { musicKitArtist in
            Artist(
                id: musicKitArtist.id.rawValue,
                name: musicKitArtist.name
            )
        }

        let startIndex = min(offset, allArtists.count)
        let endIndex = min(offset + limit, allArtists.count)
        let artists = Array(allArtists[startIndex..<endIndex])
        let hasMore = artists.count == limit

        return ArtistPage(artists: artists, hasMore: hasMore)
    }

    func searchLibraryPlaylists(query: String, limit: Int, offset: Int) async throws -> PlaylistPage {
        var request = MusicLibrarySearchRequest(term: query, types: [MusicKit.Playlist.self])
        request.limit = offset + limit

        let response = try await request.response()

        let allPlaylists = response.playlists.map { musicKitPlaylist in
            Playlist(
                id: musicKitPlaylist.id.rawValue,
                name: musicKitPlaylist.name
            )
        }

        let startIndex = min(offset, allPlaylists.count)
        let endIndex = min(offset + limit, allPlaylists.count)
        let playlists = Array(allPlaylists[startIndex..<endIndex])
        let hasMore = playlists.count == limit

        return PlaylistPage(playlists: playlists, hasMore: hasMore)
    }

    func setQueue(songs: [Song]) async throws {
        print("🎵 setQueue() called with \(songs.count) songs")
        print("🎵 Song IDs requested: \(songs.map(\.id))")
        let ids = songs.map { MusicItemID($0.id) }

        // Use MusicLibraryRequest instead of MusicCatalogResourceRequest
        var request = MusicLibraryRequest<MusicKit.Song>()
        request.filter(matching: \.id, memberOf: ids)
        print("🎵 Fetching songs from library...")
        let response = try await request.response()
        print("🎵 Got \(response.items.count) songs from library")
        print("🎵 Song IDs found: \(response.items.map { $0.id.rawValue })")

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
                print("⚠️   - missing song ID: \(song.id)")
            }
        }

        // Start from the first item in our ordered queue
        let queue = ApplicationMusicPlayer.Queue(for: orderedItems, startingAt: orderedItems.first)
        player.queue = queue
        player.state.shuffleMode = .off  // We handle shuffling ourselves
        print("🎵 setQueue() completed with \(orderedItems.count) items, starting at id=\(orderedItems.first?.id.rawValue ?? "nil")")
    }

    func insertIntoQueue(songs: [Song]) async throws {
        guard !songs.isEmpty else { return }
        print("🎵 insertIntoQueue() called with \(songs.count) songs: \(songs.map(\.id))")

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
                print("⚠️   - missing song ID: \(song.id)")
            }
        }

        // Insert all songs at once to avoid flooding MusicKit with individual requests
        // MusicKit's insert() accepts MusicItemCollection
        print("🎵 Inserting \(orderedItems.count) items at queue tail...")
        try await player.queue.insert(MusicItemCollection(orderedItems), position: .tail)
        print("🎵 insertIntoQueue() completed - inserted \(orderedItems.count) items")
    }

    func replaceQueue(queue songs: [Song], startAtSongId: String?, policy: QueueApplyPolicy) async throws {
        print("🎵 replaceQueue() called with queue=\(songs.count), startAtSongId=\(startAtSongId ?? "nil")")

        let savedPlaybackTime = player.playbackTime

        guard !songs.isEmpty else {
            print("🎵 replaceQueue() no songs to queue, returning")
            return
        }

        let ids = songs.map { MusicItemID($0.id) }

        var request = MusicLibraryRequest<MusicKit.Song>()
        request.filter(matching: \.id, memberOf: ids)
        let response = try await request.response()

        guard !response.items.isEmpty else {
            print("🎵 No songs found, returning")
            return
        }

        // Reorder response items to match our desired order
        let itemsById = Dictionary(uniqueKeysWithValues: response.items.map { ($0.id.rawValue, $0) })
        let orderedItems = songs.compactMap { itemsById[$0.id] }

        guard !orderedItems.isEmpty else {
            print("🎵 replaceQueue() no resolved MusicKit items, returning")
            return
        }

        let startItem = startAtSongId.flatMap { id in
            orderedItems.first(where: { $0.id.rawValue == id })
        } ?? orderedItems.first

        // Install full queue while selecting the desired current entry.
        let queue = ApplicationMusicPlayer.Queue(for: orderedItems, startingAt: startItem)
        player.queue = queue
        player.state.shuffleMode = .off

        switch policy {
        case .forcePlaying:
            try await player.play()
            player.playbackTime = savedPlaybackTime
            print("🎵 Queue updated in playing state at \(savedPlaybackTime)")
        case .forcePaused:
            // Prime the entry so metadata (artwork/duration) is available without autoplay.
            try? await player.prepareToPlay()
            player.pause()
            player.playbackTime = savedPlaybackTime
            print("🎵 Queue updated in paused state at \(savedPlaybackTime)")
        }

        emitCurrentState()
        print("🎵 replaceQueue() completed with \(orderedItems.count) items")
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

    private func startObservingPlaybackStateIfNeeded() {
        observationTaskLock.lock()
        defer { observationTaskLock.unlock() }
        guard stateObservationTask == nil else { return }

        stateObservationTask = Task { @MainActor [weak self] in
            guard let self else { return }

            // Initial state
            self.emitCurrentState()

            // Observe both state and queue changes from MusicKit.
            let stateChanges = self.player.state.objectWillChange.map { _ in () }
            let queueChanges = self.player.queue.objectWillChange.map { _ in () }
            let mergedChanges = Publishers.Merge(stateChanges, queueChanges)

            for await _ in mergedChanges.values {
                self.emitCurrentState()
            }
        }
    }

    private func emitCurrentState() {
        let state = mapPlaybackState()
        let didPublish = playbackStateBroadcaster.publish(state)
        #if DEBUG
        if didPublish {
            print("📻 Emitting state: \(state)")
        }
        #endif
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
            // MusicKit can report `.stopped` while a queue entry is loaded (for example after queue restore).
            // Surface that as paused-with-song so UI can show now-playing metadata without auto-playing.
            return .paused(song)
        case .interrupted:
            return .paused(song)
        case .seekingForward, .seekingBackward:
            return .playing(song)
        @unknown default:
            return .stopped
        }
    }
}

final class PlaybackStateBroadcaster {
    private var continuations: [UUID: AsyncStream<PlaybackState>.Continuation] = [:]
    private var latestState: PlaybackState = .empty
    private let lock = NSLock()

    var subscriberCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return continuations.count
    }

    func stream(replaying state: PlaybackState) -> AsyncStream<PlaybackState> {
        AsyncStream { [weak self] continuation in
            guard let self else {
                continuation.finish()
                return
            }

            let id = UUID()
            let replayState: PlaybackState

            lock.lock()
            if continuations.isEmpty {
                latestState = state
            }
            continuations[id] = continuation
            replayState = latestState
            lock.unlock()

            continuation.yield(replayState)
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.removeSubscriber(id: id)
                }
            }
        }
    }

    @discardableResult
    func publish(_ state: PlaybackState) -> Bool {
        let subscribers: [AsyncStream<PlaybackState>.Continuation]

        lock.lock()
        if state == latestState {
            lock.unlock()
            return false
        }
        latestState = state
        subscribers = Array(continuations.values)
        lock.unlock()

        for continuation in subscribers {
            continuation.yield(state)
        }
        return true
    }

    func finishAll() {
        let subscribers: [AsyncStream<PlaybackState>.Continuation]

        lock.lock()
        subscribers = Array(continuations.values)
        continuations.removeAll()
        lock.unlock()

        for continuation in subscribers {
            continuation.finish()
        }
    }

    private func removeSubscriber(id: UUID) {
        lock.lock()
        continuations.removeValue(forKey: id)
        lock.unlock()
    }
}
