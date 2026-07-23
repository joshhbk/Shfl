import Foundation
import Synchronization

/// Deterministic adapter for playback scenarios, previews, and UI tests.
///
/// It uses the same music seam as MusicKit. Catalog results are supplied at
/// construction time, and playback time advances only when `advance(by:)` is
/// called. No Apple Music account, network, or wall clock is involved.
nonisolated actor DeterministicMusicService: MusicService {
    nonisolated struct Configuration: Sendable {
        var isAuthorized = true
        var librarySongs: [Song] = []
        var libraryPlaylists: [Playlist] = []
        var playlistSongs: [String: [Song]] = [:]
        var playbackDuration: TimeInterval = 180
        var playbackTime: TimeInterval = 0
        var playbackState: PlaybackState = .empty
    }

    private nonisolated struct PlaybackSnapshot: Sendable {
        var time: TimeInterval
        var duration: TimeInterval
        var currentSongID: String?
    }

    private var authorizationResult: Bool
    private var librarySongs: [Song]
    private var libraryPlaylists: [Playlist]
    private var playlistSongs: [String: [Song]]

    private(set) var loadCallCount = 0
    private(set) var lastLoadRequest: PlaybackLoadRequest?

    private var nextLoadError: Error?
    private var currentState: PlaybackState
    private var continuations: [UUID: AsyncStream<PlaybackEvent>.Continuation] = [:]
    private var queuedSongs: [Song] = []
    private var currentIndex = 0
    private var sessionHasEnded = false
    private nonisolated let playbackSnapshot: Mutex<PlaybackSnapshot>

    init(configuration: Configuration = Configuration()) {
        authorizationResult = configuration.isAuthorized
        librarySongs = configuration.librarySongs
        libraryPlaylists = configuration.libraryPlaylists
        playlistSongs = configuration.playlistSongs
        currentState = configuration.playbackState
        playbackSnapshot = Mutex(
            PlaybackSnapshot(
                time: max(0, configuration.playbackTime),
                duration: max(0, configuration.playbackDuration),
                currentSongID: configuration.playbackState.currentSongId
            )
        )
    }

    nonisolated var playbackEvents: AsyncStream<PlaybackEvent> {
        AsyncStream { continuation in
            let id = UUID()
            Task { await self.addContinuation(continuation, id: id) }
            continuation.onTermination = { _ in
                Task { await self.removeContinuation(id: id) }
            }
        }
    }

    nonisolated var currentPlaybackTime: TimeInterval {
        playbackSnapshot.withLock { $0.time }
    }

    nonisolated var currentSongDuration: TimeInterval {
        playbackSnapshot.withLock { $0.duration }
    }

    nonisolated var currentSongId: String? {
        playbackSnapshot.withLock { $0.currentSongID }
    }

    var isAuthorized: Bool { authorizationResult }

    func requestAuthorization() async -> Bool {
        authorizationResult
    }

    func fetchLibrarySongs(
        sortedBy sortOption: SortOption,
        limit: Int,
        offset: Int
    ) async throws -> LibraryPage {
        page(sorted(librarySongs, by: sortOption), limit: limit, offset: offset)
    }

    func searchLibrarySongs(query: String, limit: Int, offset: Int) async throws -> LibraryPage {
        let matches = librarySongs.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.artist.localizedCaseInsensitiveContains(query)
        }
        return page(matches, limit: limit, offset: offset)
    }

    func searchLibraryArtists(query: String, limit: Int, offset: Int) async throws -> ArtistPage {
        let matches = artists.filter { $0.name.localizedCaseInsensitiveContains(query) }
        let bounds = pageBounds(count: matches.count, limit: limit, offset: offset)
        return ArtistPage(artists: Array(matches[bounds.range]), hasMore: bounds.hasMore)
    }

    func searchLibraryPlaylists(query: String, limit: Int, offset: Int) async throws -> PlaylistPage {
        let matches = libraryPlaylists.filter { $0.name.localizedCaseInsensitiveContains(query) }
        let bounds = pageBounds(count: matches.count, limit: limit, offset: offset)
        return PlaylistPage(playlists: Array(matches[bounds.range]), hasMore: bounds.hasMore)
    }

    func fetchLibraryArtists(limit: Int, offset: Int) async throws -> ArtistPage {
        let artists = self.artists
        let bounds = pageBounds(count: artists.count, limit: limit, offset: offset)
        return ArtistPage(artists: Array(artists[bounds.range]), hasMore: bounds.hasMore)
    }

    func fetchLibraryPlaylists(limit: Int, offset: Int) async throws -> PlaylistPage {
        let bounds = pageBounds(count: libraryPlaylists.count, limit: limit, offset: offset)
        return PlaylistPage(playlists: Array(libraryPlaylists[bounds.range]), hasMore: bounds.hasMore)
    }

    func fetchSongs(byArtist artistName: String, limit: Int, offset: Int) async throws -> LibraryPage {
        let songs = librarySongs.filter { $0.artist == artistName }
        return page(songs, limit: limit, offset: offset)
    }

    func fetchSongs(byPlaylistId playlistId: String, limit: Int, offset: Int) async throws -> LibraryPage {
        page(playlistSongs[playlistId] ?? [], limit: limit, offset: offset)
    }

    func load(_ request: PlaybackLoadRequest) async throws {
        if let nextLoadError {
            self.nextLoadError = nil
            throw nextLoadError
        }
        guard !request.queue.isEmpty else { throw PlaybackLoadError.emptyQueue }
        guard let index = request.queue.firstIndex(where: { $0.id == request.currentSongID }) else {
            throw PlaybackLoadError.currentSongMissing(request.currentSongID)
        }

        loadCallCount += 1
        lastLoadRequest = request
        queuedSongs = request.queue
        currentIndex = index
        sessionHasEnded = false
        updateSnapshot(time: request.playbackPosition)
        updateCurrentSongID(request.currentSongID)
        publish(
            .stateChanged(
                request.autoplay
                    ? .playing(queuedSongs[index])
                    : .paused(queuedSongs[index])
            )
        )
    }

    func play() async throws {
        guard queuedSongs.indices.contains(currentIndex) else { return }
        publish(.stateChanged(.playing(queuedSongs[currentIndex])))
    }

    func pause() async {
        guard let song = currentState.currentSong else { return }
        publish(.stateChanged(.paused(song)))
    }

    func skipToNext() async throws {
        guard !queuedSongs.isEmpty else { return }
        guard currentIndex + 1 < queuedSongs.count else {
            finishSession()
            return
        }
        currentIndex += 1
        updateSnapshot(time: 0)
        updateCurrentSongID(queuedSongs[currentIndex].id)
        publish(.stateChanged(.playing(queuedSongs[currentIndex])))
    }

    func skipToPrevious() async throws {
        guard !queuedSongs.isEmpty else { return }
        currentIndex = max(0, currentIndex - 1)
        updateSnapshot(time: 0)
        updateCurrentSongID(queuedSongs[currentIndex].id)
        publish(.stateChanged(.playing(queuedSongs[currentIndex])))
    }

    func restartOrSkipToPrevious() async throws {
        if currentPlaybackTime > 3 {
            seek(to: 0)
        } else {
            try await skipToPrevious()
        }
    }

    nonisolated func seek(to time: TimeInterval) {
        playbackSnapshot.withLock { $0.time = max(0, time) }
    }

    func clear() async {
        queuedSongs = []
        currentIndex = 0
        sessionHasEnded = false
        updateSnapshot(time: 0)
        updateCurrentSongID(nil)
        publish(.stateChanged(.empty))
    }

    /// Advances virtual playback and emits the same normalized events as the
    /// MusicKit adapter. Natural session completion never wraps the queue.
    func advance(by interval: TimeInterval) {
        guard interval > 0,
              currentState.isPlaying,
              !queuedSongs.isEmpty,
              currentSongDuration > 0 else { return }

        var remaining = interval
        while remaining > 0 {
            let time = currentPlaybackTime
            let untilBoundary = max(0, currentSongDuration - time)
            if remaining < untilBoundary {
                updateSnapshot(time: time + remaining)
                return
            }
            remaining -= untilBoundary
            if currentIndex + 1 >= queuedSongs.count {
                finishSession()
                return
            }
            currentIndex += 1
            updateSnapshot(time: 0)
            updateCurrentSongID(queuedSongs[currentIndex].id)
            publish(.stateChanged(.playing(queuedSongs[currentIndex])))
        }
    }

    func simulatePlaybackState(_ state: PlaybackState) {
        updateCurrentSongID(state.currentSongId)
        if state == .empty {
            updateSnapshot(time: 0)
        }
        publish(.stateChanged(state))
    }

    func simulateSessionEnded() {
        finishSession()
    }

    func setLibrarySongs(_ songs: [Song]) {
        librarySongs = songs
    }

    func setPlaybackTime(_ time: TimeInterval) {
        updateSnapshot(time: time)
    }

    func setPlaybackDuration(_ duration: TimeInterval) {
        playbackSnapshot.withLock { $0.duration = max(0, duration) }
    }

    func failNextLoad(with error: Error?) {
        nextLoadError = error
    }

    func resetPlaybackRecording() {
        loadCallCount = 0
        lastLoadRequest = nil
        nextLoadError = nil
    }

    private func addContinuation(
        _ continuation: AsyncStream<PlaybackEvent>.Continuation,
        id: UUID
    ) {
        continuations[id] = continuation
        continuation.yield(.stateChanged(currentState))
        if sessionHasEnded {
            continuation.yield(.sessionEnded)
        }
    }

    private func removeContinuation(id: UUID) {
        continuations.removeValue(forKey: id)
    }

    private func publish(_ event: PlaybackEvent) {
        if case .stateChanged(let state) = event {
            currentState = state
        }
        continuations.values.forEach { $0.yield(event) }
    }

    private func finishSession() {
        sessionHasEnded = true
        updateSnapshot(time: 0)
        updateCurrentSongID(nil)
        publish(.stateChanged(.stopped))
        publish(.sessionEnded)
    }

    private nonisolated func updateSnapshot(time: TimeInterval) {
        playbackSnapshot.withLock { $0.time = max(0, time) }
    }

    private nonisolated func updateCurrentSongID(_ songID: String?) {
        playbackSnapshot.withLock { $0.currentSongID = songID }
    }

    private func sorted(_ songs: [Song], by option: SortOption) -> [Song] {
        switch option {
        case .mostPlayed:
            songs.sorted {
                if $0.playCount != $1.playCount {
                    return $0.playCount > $1.playCount
                }
                return $0.id < $1.id
            }
        case .recentlyPlayed:
            songs.sorted {
                let leftDate = $0.lastPlayedDate ?? .distantPast
                let rightDate = $1.lastPlayedDate ?? .distantPast
                if leftDate != rightDate {
                    return leftDate > rightDate
                }
                return $0.id < $1.id
            }
        case .recentlyAdded:
            songs
        case .alphabetical:
            songs.sorted {
                let comparison = $0.title.localizedCaseInsensitiveCompare($1.title)
                return comparison == .orderedSame ? $0.id < $1.id : comparison == .orderedAscending
            }
        }
    }

    private var artists: [Artist] {
        Set(librarySongs.map(\.artist))
            .sorted()
            .map { Artist(id: $0, name: $0) }
    }

    private func page(_ songs: [Song], limit: Int, offset: Int) -> LibraryPage {
        let bounds = pageBounds(count: songs.count, limit: limit, offset: offset)
        return LibraryPage(songs: Array(songs[bounds.range]), hasMore: bounds.hasMore)
    }

    private func pageBounds(
        count: Int,
        limit: Int,
        offset: Int
    ) -> (range: Range<Int>, hasMore: Bool) {
        let safeOffset = max(0, offset)
        let safeLimit = max(0, limit)
        let start = min(safeOffset, count)
        let end = min(start + safeLimit, count)
        return (start..<end, end < count)
    }
}
