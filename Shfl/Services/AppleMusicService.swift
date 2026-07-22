import Combine
import Foundation
import MusicKit

private enum AppleMusicServiceError: LocalizedError {
    case incompleteQueueResolution(missingSongIds: [String])

    var errorDescription: String? {
        switch self {
        case .incompleteQueueResolution(let missingSongIds):
            return "Apple Music could not resolve every queued song: \(missingSongIds.joined(separator: ", "))."
        }
    }
}

final class AppleMusicService: MusicService {
    private let player = ApplicationMusicPlayer.shared
    private var stateObservationTask: Task<Void, Never>?
    private let observationTaskLock = NSLock()
    private let playbackEventBroadcaster = PlaybackEventBroadcaster()
    private var loadedFinalSongID: String?
    private var lastObservedSongID: String?
    private var hasObservedPlaying = false
    private var didPublishSessionEnd = false
    private var sessionEndConfirmationTask: Task<Void, Never>?

    var playbackEvents: AsyncStream<PlaybackEvent> {
        let currentState = mapPlaybackState()
        let stream = playbackEventBroadcaster.stream(
            replaying: .stateChanged(currentState)
        )
        startObservingPlaybackStateIfNeeded()
        return stream
    }

    deinit {
        observationTaskLock.lock()
        let task = stateObservationTask
        stateObservationTask = nil
        observationTaskLock.unlock()
        task?.cancel()
        sessionEndConfirmationTask?.cancel()
        playbackEventBroadcaster.finishAll()
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

    func load(_ request: PlaybackLoadRequest) async throws {
        let songs = request.queue
        guard !songs.isEmpty else {
            throw PlaybackLoadError.emptyQueue
        }
        guard songs.contains(where: { $0.id == request.currentSongID }) else {
            throw PlaybackLoadError.currentSongMissing(request.currentSongID)
        }

        let ids = songs.map { MusicItemID($0.id) }
        var libraryRequest = MusicLibraryRequest<MusicKit.Song>()
        libraryRequest.limit = ids.count
        libraryRequest.filter(matching: \.id, memberOf: ids)
        let response = try await libraryRequest.response()

        let itemsById = Dictionary(uniqueKeysWithValues: response.items.map { ($0.id.rawValue, $0) })
        let orderedItems = songs.compactMap { itemsById[$0.id] }
        let missingSongIds = songs.compactMap { itemsById[$0.id] == nil ? $0.id : nil }
        guard missingSongIds.isEmpty else {
            throw AppleMusicServiceError.incompleteQueueResolution(missingSongIds: missingSongIds)
        }

        guard let startItem = orderedItems.first(where: {
            $0.id.rawValue == request.currentSongID
        }) else {
            throw PlaybackLoadError.currentSongMissing(request.currentSongID)
        }

        let queue = ApplicationMusicPlayer.Queue(for: orderedItems, startingAt: startItem)
        player.queue = queue
        player.state.shuffleMode = .off
        loadedFinalSongID = orderedItems.last?.id.rawValue
        lastObservedSongID = startItem.id.rawValue
        hasObservedPlaying = false
        didPublishSessionEnd = false
        sessionEndConfirmationTask?.cancel()

        do {
            try? await player.prepareToPlay()
            player.playbackTime = max(0, request.playbackPosition)
            if request.autoplay {
                try await player.play()
                player.playbackTime = max(0, request.playbackPosition)
            } else {
                player.pause()
            }
        } catch {
            await clear()
            throw error
        }
        emitCurrentState()
    }

    func clear() async {
        loadedFinalSongID = nil
        lastObservedSongID = nil
        hasObservedPlaying = false
        didPublishSessionEnd = false
        sessionEndConfirmationTask?.cancel()
        player.pause()
        player.queue = []
        emitCurrentState()
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
        if let songID = state.currentSongId {
            lastObservedSongID = songID
        }
        if state.isPlaying {
            hasObservedPlaying = true
            sessionEndConfirmationTask?.cancel()
            sessionEndConfirmationTask = nil
        }

        let rawStopped = player.state.playbackStatus == .stopped
        let reachedLoadedEnd = loadedFinalSongID != nil
            && lastObservedSongID == loadedFinalSongID
            && hasObservedPlaying
            && (state == .empty || rawStopped)

        let didPublish = playbackEventBroadcaster.publish(.stateChanged(state))
        if reachedLoadedEnd && !didPublishSessionEnd {
            scheduleSessionEndConfirmation()
        }
        #if DEBUG
        if didPublish {
            print("📻 Emitting state: \(state)")
        }
        #endif
    }

    private func scheduleSessionEndConfirmation() {
        guard sessionEndConfirmationTask == nil else { return }
        let expectedFinalSongID = loadedFinalSongID
        sessionEndConfirmationTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, let self else { return }
            self.sessionEndConfirmationTask = nil

            let stillStopped = self.player.state.playbackStatus == .stopped
                || self.player.queue.currentEntry == nil
            guard stillStopped,
                  self.loadedFinalSongID == expectedFinalSongID,
                  self.lastObservedSongID == expectedFinalSongID,
                  self.hasObservedPlaying,
                  !self.didPublishSessionEnd else {
                return
            }

            self.didPublishSessionEnd = true
            self.playbackEventBroadcaster.publish(.sessionEnded)
        }
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

final class PlaybackEventBroadcaster {
    private var continuations: [UUID: AsyncStream<PlaybackEvent>.Continuation] = [:]
    private var latestEvent: PlaybackEvent = .stateChanged(.empty)
    private let lock = NSLock()

    var subscriberCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return continuations.count
    }

    func stream(replaying event: PlaybackEvent) -> AsyncStream<PlaybackEvent> {
        AsyncStream { [weak self] continuation in
            guard let self else {
                continuation.finish()
                return
            }

            let id = UUID()
            let replayEvent: PlaybackEvent

            lock.lock()
            if continuations.isEmpty {
                latestEvent = event
            }
            continuations[id] = continuation
            replayEvent = latestEvent
            lock.unlock()

            continuation.yield(replayEvent)
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.removeSubscriber(id: id)
                }
            }
        }
    }

    @discardableResult
    func publish(_ event: PlaybackEvent) -> Bool {
        let subscribers: [AsyncStream<PlaybackEvent>.Continuation]

        lock.lock()
        if event == latestEvent {
            lock.unlock()
            return false
        }
        latestEvent = event
        subscribers = Array(continuations.values)
        lock.unlock()

        for continuation in subscribers {
            continuation.yield(event)
        }
        return true
    }

    func finishAll() {
        let subscribers: [AsyncStream<PlaybackEvent>.Continuation]

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
