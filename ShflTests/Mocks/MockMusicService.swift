import Foundation
@testable import Shfl

actor MockMusicService: MusicService {
    var authorizationResult: Bool = true
    var searchResults: [Song] = []
    var shouldThrowOnPlay: Error?
    var shouldThrowOnSearch: Error?
    var shouldThrowOnSkip: Error?
    var librarySongs: [Song] = []
    var setQueueCallCount: Int = 0
    var replaceQueueCallCount: Int = 0
    var playCallCount: Int = 0
    var pauseCallCount: Int = 0
    nonisolated(unsafe) var seekCallCount: Int = 0
    nonisolated(unsafe) var lastSeekTime: TimeInterval = 0
    var lastQueuedSongs: [Song] = []
    var shouldThrowOnReplace: Error?
    var shouldThrowOnFetch: Error?
    var setQueueDelayNanoseconds: UInt64 = 0
    var replaceQueueDelayNanoseconds: UInt64 = 0

    /// Configurable duration for testing. Access via currentSongDuration.
    nonisolated(unsafe) var mockDuration: TimeInterval = 180

    /// Configurable playback time for testing position preservation
    nonisolated(unsafe) var mockPlaybackTime: TimeInterval = 0

    private var currentState: PlaybackState = .empty
    private var continuation: AsyncStream<PlaybackState>.Continuation?
    private var queuedSongs: [Song] = []
    private var currentIndex: Int = 0

    nonisolated var playbackStateStream: AsyncStream<PlaybackState> {
        AsyncStream { continuation in
            Task { await self.setContinuation(continuation) }
        }
    }

    nonisolated var currentPlaybackTime: TimeInterval { mockPlaybackTime }
    nonisolated var currentSongDuration: TimeInterval { mockDuration }
    nonisolated var currentSongId: String? { mockCurrentSongId }
    nonisolated(unsafe) var mockCurrentSongId: String?

    nonisolated var transportQueueEntryCount: Int { mockTransportQueueEntryCount }
    nonisolated(unsafe) var mockTransportQueueEntryCount: Int = 0

    private func setContinuation(_ cont: AsyncStream<PlaybackState>.Continuation) {
        self.continuation = cont
        cont.yield(currentState)
    }

    func requestAuthorization() async -> Bool {
        authorizationResult
    }

    var isAuthorized: Bool {
        authorizationResult
    }

    func fetchLibrarySongs(
        sortedBy: SortOption,
        limit: Int,
        offset: Int
    ) async throws -> LibraryPage {
        if let error = shouldThrowOnFetch {
            throw error
        }
        let startIndex = min(offset, librarySongs.count)
        let endIndex = min(offset + limit, librarySongs.count)
        let pageItems = Array(librarySongs[startIndex..<endIndex])
        let hasMore = endIndex < librarySongs.count
        return LibraryPage(songs: pageItems, hasMore: hasMore)
    }

    var libraryArtists: [Artist] = []
    var libraryPlaylists: [Playlist] = []
    var artistSongs: [String: [Song]] = [:]
    var playlistSongs: [String: [Song]] = [:]

    func searchLibraryArtists(query: String, limit: Int, offset: Int) async throws -> ArtistPage {
        if let error = shouldThrowOnSearch { throw error }
        let filtered = libraryArtists.filter {
            $0.name.localizedCaseInsensitiveContains(query)
        }
        let startIndex = min(offset, filtered.count)
        let endIndex = min(offset + limit, filtered.count)
        let pageItems = Array(filtered[startIndex..<endIndex])
        let hasMore = endIndex < filtered.count
        return ArtistPage(artists: pageItems, hasMore: hasMore)
    }

    func searchLibraryPlaylists(query: String, limit: Int, offset: Int) async throws -> PlaylistPage {
        if let error = shouldThrowOnSearch { throw error }
        let filtered = libraryPlaylists.filter {
            $0.name.localizedCaseInsensitiveContains(query)
        }
        let startIndex = min(offset, filtered.count)
        let endIndex = min(offset + limit, filtered.count)
        let pageItems = Array(filtered[startIndex..<endIndex])
        let hasMore = endIndex < filtered.count
        return PlaylistPage(playlists: pageItems, hasMore: hasMore)
    }

    func fetchLibraryArtists(limit: Int, offset: Int) async throws -> ArtistPage {
        if let error = shouldThrowOnFetch { throw error }
        let startIndex = min(offset, libraryArtists.count)
        let endIndex = min(offset + limit, libraryArtists.count)
        let pageItems = Array(libraryArtists[startIndex..<endIndex])
        let hasMore = endIndex < libraryArtists.count
        return ArtistPage(artists: pageItems, hasMore: hasMore)
    }

    func fetchLibraryPlaylists(limit: Int, offset: Int) async throws -> PlaylistPage {
        if let error = shouldThrowOnFetch { throw error }
        let startIndex = min(offset, libraryPlaylists.count)
        let endIndex = min(offset + limit, libraryPlaylists.count)
        let pageItems = Array(libraryPlaylists[startIndex..<endIndex])
        let hasMore = endIndex < libraryPlaylists.count
        return PlaylistPage(playlists: pageItems, hasMore: hasMore)
    }

    func fetchSongs(byArtist artistName: String, limit: Int, offset: Int) async throws -> LibraryPage {
        if let error = shouldThrowOnFetch { throw error }
        let songs = artistSongs[artistName] ?? librarySongs.filter { $0.artist == artistName }
        let startIndex = min(offset, songs.count)
        let endIndex = min(offset + limit, songs.count)
        let pageItems = Array(songs[startIndex..<endIndex])
        let hasMore = endIndex < songs.count
        return LibraryPage(songs: pageItems, hasMore: hasMore)
    }

    func fetchSongs(byPlaylistId playlistId: String, limit: Int, offset: Int) async throws -> LibraryPage {
        if let error = shouldThrowOnFetch { throw error }
        let songs = playlistSongs[playlistId] ?? []
        let startIndex = min(offset, songs.count)
        let endIndex = min(offset + limit, songs.count)
        let pageItems = Array(songs[startIndex..<endIndex])
        let hasMore = endIndex < songs.count
        return LibraryPage(songs: pageItems, hasMore: hasMore)
    }

    func searchLibrarySongs(query: String, limit: Int, offset: Int) async throws -> LibraryPage {
        if let error = shouldThrowOnSearch {
            throw error
        }
        let filtered = librarySongs.filter {
            $0.title.localizedCaseInsensitiveContains(query) ||
            $0.artist.localizedCaseInsensitiveContains(query)
        }
        let startIndex = min(offset, filtered.count)
        let endIndex = min(offset + limit, filtered.count)
        let pageItems = Array(filtered[startIndex..<endIndex])
        let hasMore = endIndex < filtered.count
        return LibraryPage(songs: pageItems, hasMore: hasMore)
    }

    func setQueue(songs: [Song]) async throws {
        if setQueueDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: setQueueDelayNanoseconds)
        }
        setQueueCallCount += 1
        lastQueuedSongs = songs
        queuedSongs = songs  // Don't shuffle - let QueueShuffler handle it
        currentIndex = 0
        mockTransportQueueEntryCount = queuedSongs.count

        switch currentState {
        case .playing, .paused:
            break
        default:
            if queuedSongs.isEmpty {
                updateState(.empty)
            } else {
                updateState(.stopped)
            }
        }
    }

    func replaceQueue(queue: [Song], startAtSongId: String?, policy: QueueApplyPolicy) async throws {
        if replaceQueueDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: replaceQueueDelayNanoseconds)
        }
        if let error = shouldThrowOnReplace {
            throw error
        }
        replaceQueueCallCount += 1
        queuedSongs = queue
        lastQueuedSongs = queuedSongs
        mockTransportQueueEntryCount = queuedSongs.count
        if let startAtSongId,
           let queueIndex = queuedSongs.firstIndex(where: { $0.id == startAtSongId }) {
            currentIndex = queueIndex
        } else {
            currentIndex = 0
        }
        if case .forcePaused = policy {
            if case .playing(let song) = currentState {
                updateState(.paused(song))
            }
        }
    }

    func play() async throws {
        playCallCount += 1
        if let error = shouldThrowOnPlay {
            throw error
        }
        guard !queuedSongs.isEmpty else { return }
        let song = queuedSongs[currentIndex]
        updateState(.playing(song))
    }

    func pause() async {
        pauseCallCount += 1
        if case .playing(let song) = currentState {
            updateState(.paused(song))
        }
    }

    func pauseImmediately() {
        pauseCallCount += 1
        if case .playing(let song) = currentState {
            updateState(.paused(song))
        }
    }

    func skipToNext() async throws {
        if let error = shouldThrowOnSkip {
            throw error
        }
        guard !queuedSongs.isEmpty else { return }
        currentIndex = (currentIndex + 1) % queuedSongs.count
        let song = queuedSongs[currentIndex]
        updateState(.playing(song))
    }

    func skipToPrevious() async throws {
        guard !queuedSongs.isEmpty else { return }
        currentIndex = (currentIndex - 1 + queuedSongs.count) % queuedSongs.count
        let song = queuedSongs[currentIndex]
        updateState(.playing(song))
    }

    func restartOrSkipToPrevious() async throws {
        // For testing, just skip to previous
        try await skipToPrevious()
    }

    nonisolated func seek(to time: TimeInterval) {
        // Track seek calls for testing using nonisolated(unsafe) vars
        seekCallCount += 1
        lastSeekTime = time
    }

    /// Call this from tests to set mock playback time before adding songs
    func setMockPlaybackTime(_ time: TimeInterval) {
        mockPlaybackTime = time
    }

    private func updateState(_ state: PlaybackState) {
        currentState = state
        continuation?.yield(state)
    }

    // Test helpers
    func setLibrarySongs(_ songs: [Song]) {
        librarySongs = songs
    }

    func simulatePlaybackState(_ state: PlaybackState) {
        updateState(state)
    }

    func setShouldThrowOnPlay(_ error: Error?) {
        shouldThrowOnPlay = error
    }

    func setShouldThrowOnReplace(_ error: Error?) {
        shouldThrowOnReplace = error
    }

    func setSetQueueDelay(nanoseconds: UInt64) {
        setQueueDelayNanoseconds = nanoseconds
    }

    func setReplaceQueueDelay(nanoseconds: UInt64) {
        replaceQueueDelayNanoseconds = nanoseconds
    }

    func resetQueueTracking() {
        setQueueCallCount = 0
        replaceQueueCallCount = 0
        playCallCount = 0
        pauseCallCount = 0
        seekCallCount = 0
        lastSeekTime = 0
        lastQueuedSongs = []
        shouldThrowOnReplace = nil
        setQueueDelayNanoseconds = 0
        replaceQueueDelayNanoseconds = 0
    }
}
