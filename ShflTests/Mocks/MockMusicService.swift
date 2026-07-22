import Foundation
@testable import Shfl

/// Deterministic MusicKit replacement used by product-level playback scenarios.
/// Time advances only when a test calls `advance(by:)`.
actor MockMusicService: MusicService {
    var authorizationResult = true
    var shouldThrowOnPlay: Error?
    var shouldThrowOnSearch: Error?
    var shouldThrowOnSkip: Error?
    var shouldThrowOnFetch: Error?
    var shouldThrowOnLoad: Error?

    var librarySongs: [Song] = []
    var libraryArtists: [Artist] = []
    var libraryPlaylists: [Playlist] = []
    var artistSongs: [String: [Song]] = [:]
    var playlistSongs: [String: [Song]] = [:]

    var loadCallCount = 0
    var playCallCount = 0
    var pauseCallCount = 0
    var lastLoadRequest: PlaybackLoadRequest?
    var lastQueuedSongs: [Song] = []

    // Temporary aliases used by a small number of migration tests.
    var replaceQueueCallCount: Int { loadCallCount }

    nonisolated(unsafe) var mockDuration: TimeInterval = 180
    nonisolated(unsafe) var mockPlaybackTime: TimeInterval = 0
    nonisolated(unsafe) var mockCurrentSongId: String?
    nonisolated(unsafe) var seekCallCount = 0
    nonisolated(unsafe) var lastSeekTime: TimeInterval = 0

    private var currentState: PlaybackState = .empty
    private var continuations: [UUID: AsyncStream<PlaybackEvent>.Continuation] = [:]
    private var queuedSongs: [Song] = []
    private var currentIndex = 0
    private var sessionHasEnded = false

    nonisolated var playbackEvents: AsyncStream<PlaybackEvent> {
        AsyncStream { continuation in
            let id = UUID()
            Task { await self.addContinuation(continuation, id: id) }
            continuation.onTermination = { _ in
                Task { await self.removeContinuation(id: id) }
            }
        }
    }

    nonisolated var currentPlaybackTime: TimeInterval { mockPlaybackTime }
    nonisolated var currentSongDuration: TimeInterval { mockDuration }
    nonisolated var currentSongId: String? { mockCurrentSongId }

    var isAuthorized: Bool { authorizationResult }
    func requestAuthorization() async -> Bool { authorizationResult }

    func fetchLibrarySongs(
        sortedBy: SortOption,
        limit: Int,
        offset: Int
    ) async throws -> LibraryPage {
        if let shouldThrowOnFetch { throw shouldThrowOnFetch }
        return page(librarySongs, limit: limit, offset: offset)
    }

    func searchLibrarySongs(query: String, limit: Int, offset: Int) async throws -> LibraryPage {
        if let shouldThrowOnSearch { throw shouldThrowOnSearch }
        let matches = librarySongs.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.artist.localizedCaseInsensitiveContains(query)
        }
        return page(matches, limit: limit, offset: offset)
    }

    func searchLibraryArtists(query: String, limit: Int, offset: Int) async throws -> ArtistPage {
        if let shouldThrowOnSearch { throw shouldThrowOnSearch }
        let matches = libraryArtists.filter { $0.name.localizedCaseInsensitiveContains(query) }
        let bounds = pageBounds(count: matches.count, limit: limit, offset: offset)
        return ArtistPage(
            artists: Array(matches[bounds.range]),
            hasMore: bounds.hasMore
        )
    }

    func searchLibraryPlaylists(query: String, limit: Int, offset: Int) async throws -> PlaylistPage {
        if let shouldThrowOnSearch { throw shouldThrowOnSearch }
        let matches = libraryPlaylists.filter { $0.name.localizedCaseInsensitiveContains(query) }
        let bounds = pageBounds(count: matches.count, limit: limit, offset: offset)
        return PlaylistPage(
            playlists: Array(matches[bounds.range]),
            hasMore: bounds.hasMore
        )
    }

    func fetchLibraryArtists(limit: Int, offset: Int) async throws -> ArtistPage {
        if let shouldThrowOnFetch { throw shouldThrowOnFetch }
        let bounds = pageBounds(count: libraryArtists.count, limit: limit, offset: offset)
        return ArtistPage(
            artists: Array(libraryArtists[bounds.range]),
            hasMore: bounds.hasMore
        )
    }

    func fetchLibraryPlaylists(limit: Int, offset: Int) async throws -> PlaylistPage {
        if let shouldThrowOnFetch { throw shouldThrowOnFetch }
        let bounds = pageBounds(count: libraryPlaylists.count, limit: limit, offset: offset)
        return PlaylistPage(
            playlists: Array(libraryPlaylists[bounds.range]),
            hasMore: bounds.hasMore
        )
    }

    func fetchSongs(byArtist artistName: String, limit: Int, offset: Int) async throws -> LibraryPage {
        if let shouldThrowOnFetch { throw shouldThrowOnFetch }
        let songs = artistSongs[artistName] ?? librarySongs.filter { $0.artist == artistName }
        return page(songs, limit: limit, offset: offset)
    }

    func fetchSongs(byPlaylistId playlistId: String, limit: Int, offset: Int) async throws -> LibraryPage {
        if let shouldThrowOnFetch { throw shouldThrowOnFetch }
        return page(playlistSongs[playlistId] ?? [], limit: limit, offset: offset)
    }

    func load(_ request: PlaybackLoadRequest) async throws {
        if let shouldThrowOnLoad { throw shouldThrowOnLoad }
        guard !request.queue.isEmpty else { throw PlaybackLoadError.emptyQueue }
        guard let index = request.queue.firstIndex(where: {
            $0.id == request.currentSongID
        }) else {
            throw PlaybackLoadError.currentSongMissing(request.currentSongID)
        }

        loadCallCount += 1
        lastLoadRequest = request
        lastQueuedSongs = request.queue
        queuedSongs = request.queue
        currentIndex = index
        sessionHasEnded = false
        mockCurrentSongId = request.currentSongID
        mockPlaybackTime = max(0, request.playbackPosition)
        publish(.stateChanged(
            request.autoplay
                ? .playing(queuedSongs[index])
                : .paused(queuedSongs[index])
        ))
    }

    func play() async throws {
        if let shouldThrowOnPlay { throw shouldThrowOnPlay }
        guard queuedSongs.indices.contains(currentIndex) else { return }
        playCallCount += 1
        publish(.stateChanged(.playing(queuedSongs[currentIndex])))
    }

    func pause() async {
        pauseCallCount += 1
        guard let song = currentState.currentSong else { return }
        publish(.stateChanged(.paused(song)))
    }

    func skipToNext() async throws {
        if let shouldThrowOnSkip { throw shouldThrowOnSkip }
        guard !queuedSongs.isEmpty else { return }
        guard currentIndex + 1 < queuedSongs.count else {
            finishSession()
            return
        }
        currentIndex += 1
        mockPlaybackTime = 0
        mockCurrentSongId = queuedSongs[currentIndex].id
        publish(.stateChanged(.playing(queuedSongs[currentIndex])))
    }

    func skipToPrevious() async throws {
        guard !queuedSongs.isEmpty else { return }
        currentIndex = max(0, currentIndex - 1)
        mockPlaybackTime = 0
        mockCurrentSongId = queuedSongs[currentIndex].id
        publish(.stateChanged(.playing(queuedSongs[currentIndex])))
    }

    func restartOrSkipToPrevious() async throws {
        if mockPlaybackTime > 3 {
            seek(to: 0)
        } else {
            try await skipToPrevious()
        }
    }

    nonisolated func seek(to time: TimeInterval) {
        seekCallCount += 1
        lastSeekTime = max(0, time)
        mockPlaybackTime = max(0, time)
    }

    func clear() async {
        queuedSongs = []
        currentIndex = 0
        sessionHasEnded = false
        mockPlaybackTime = 0
        mockCurrentSongId = nil
        publish(.stateChanged(.empty))
    }

    func advance(by interval: TimeInterval) {
        guard interval > 0, currentState.isPlaying, !queuedSongs.isEmpty else { return }
        var remaining = interval
        while remaining > 0 {
            let untilBoundary = max(0, mockDuration - mockPlaybackTime)
            if remaining < untilBoundary {
                mockPlaybackTime += remaining
                return
            }
            remaining -= untilBoundary
            if currentIndex + 1 >= queuedSongs.count {
                finishSession()
                return
            }
            currentIndex += 1
            mockPlaybackTime = 0
            mockCurrentSongId = queuedSongs[currentIndex].id
            publish(.stateChanged(.playing(queuedSongs[currentIndex])))
        }
    }

    func simulatePlaybackState(_ state: PlaybackState) {
        if let song = state.currentSong {
            mockCurrentSongId = song.id
        } else if state == .empty {
            mockCurrentSongId = nil
            mockPlaybackTime = 0
        }
        publish(.stateChanged(state))
    }

    func simulateSessionEnded() {
        finishSession()
    }

    func setLibrarySongs(_ songs: [Song]) { librarySongs = songs }
    func setMockPlaybackTime(_ time: TimeInterval) { mockPlaybackTime = time }
    func setShouldThrowOnPlay(_ error: Error?) { shouldThrowOnPlay = error }
    func setShouldThrowOnLoad(_ error: Error?) { shouldThrowOnLoad = error }
    func setShouldThrowOnReplace(_ error: Error?) { shouldThrowOnLoad = error }

    func resetQueueTracking() {
        loadCallCount = 0
        playCallCount = 0
        pauseCallCount = 0
        seekCallCount = 0
        lastSeekTime = 0
        lastLoadRequest = nil
        lastQueuedSongs = []
        shouldThrowOnLoad = nil
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
        mockPlaybackTime = 0
        mockCurrentSongId = nil
        publish(.stateChanged(.stopped))
        publish(.sessionEnded)
    }

    private func page(_ songs: [Song], limit: Int, offset: Int) -> LibraryPage {
        let bounds = pageBounds(count: songs.count, limit: limit, offset: offset)
        return LibraryPage(
            songs: Array(songs[bounds.range]),
            hasMore: bounds.hasMore
        )
    }

    private func pageBounds(
        count: Int,
        limit: Int,
        offset: Int
    ) -> (range: Range<Int>, hasMore: Bool) {
        let start = min(offset, count)
        let end = min(start + limit, count)
        return (start..<end, end < count)
    }
}
