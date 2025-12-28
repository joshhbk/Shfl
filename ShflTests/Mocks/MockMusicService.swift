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
    var lastQueuedSongs: [Song] = []
    var shouldThrowOnFetch: Error?

    /// Configurable duration for testing. Access via currentSongDuration.
    nonisolated(unsafe) var mockDuration: TimeInterval = 180

    private var currentState: PlaybackState = .empty
    private var continuation: AsyncStream<PlaybackState>.Continuation?
    private var queuedSongs: [Song] = []
    private var currentIndex: Int = 0

    nonisolated var playbackStateStream: AsyncStream<PlaybackState> {
        AsyncStream { continuation in
            Task { await self.setContinuation(continuation) }
        }
    }

    nonisolated var currentPlaybackTime: TimeInterval { 0 }
    nonisolated var currentSongDuration: TimeInterval { mockDuration }

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
        queuedSongs = songs.shuffled()
        currentIndex = 0

        // Only change state if not actively playing/paused
        // Real Apple Music preserves playback when queue is updated
        switch currentState {
        case .playing, .paused:
            // Keep current playback state - queue update doesn't stop playback
            break
        default:
            if queuedSongs.isEmpty {
                updateState(.empty)
            } else {
                updateState(.stopped)
            }
        }
    }

    func setInitialQueue(songs: [Song]) async throws {
        // For testing, behaves like setQueue with a subset
        try await setQueue(songs: songs)
    }

    func appendToQueue(songs: [Song]) async throws {
        // For testing, append to existing queue
        queuedSongs.append(contentsOf: songs)
        lastQueuedSongs.append(contentsOf: songs)
    }

    func play() async throws {
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
        lastQueuedSongs = []
    }
}
