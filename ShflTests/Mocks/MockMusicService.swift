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
    var insertIntoQueueCallCount: Int = 0
    var replaceUpcomingQueueCallCount: Int = 0
    var playCallCount: Int = 0
    nonisolated(unsafe) var seekCallCount: Int = 0
    nonisolated(unsafe) var lastSeekTime: TimeInterval = 0
    var lastQueuedSongs: [Song] = []
    var lastInsertedSongs: [Song] = []
    var shouldThrowOnFetch: Error?

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

    func searchLibrarySongs(query: String) async throws -> [Song] {
        if let error = shouldThrowOnSearch {
            throw error
        }
        return librarySongs.filter {
            $0.title.localizedCaseInsensitiveContains(query) ||
            $0.artist.localizedCaseInsensitiveContains(query)
        }
    }

    func setQueue(songs: [Song]) async throws {
        setQueueCallCount += 1
        lastQueuedSongs = songs
        queuedSongs = songs  // Don't shuffle - let QueueShuffler handle it
        currentIndex = 0

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

    func insertIntoQueue(songs: [Song]) async throws {
        insertIntoQueueCallCount += 1
        lastInsertedSongs = songs
        // Append to existing queue without disrupting playback
        queuedSongs.append(contentsOf: songs)
        lastQueuedSongs = queuedSongs
    }

    func replaceUpcomingQueue(with songs: [Song], currentSong: Song) async throws {
        replaceUpcomingQueueCallCount += 1
        // Replace queue while preserving current song
        queuedSongs = [currentSong] + songs
        lastQueuedSongs = queuedSongs
        currentIndex = 0
        // Don't call play() - preserves current playback position
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

    func resetQueueTracking() {
        setQueueCallCount = 0
        insertIntoQueueCallCount = 0
        replaceUpcomingQueueCallCount = 0
        playCallCount = 0
        seekCallCount = 0
        lastSeekTime = 0
        lastQueuedSongs = []
        lastInsertedSongs = []
    }
}
