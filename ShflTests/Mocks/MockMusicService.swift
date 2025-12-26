import Foundation
@testable import Shfl

actor MockMusicService: MusicService {
    var authorizationResult: Bool = true
    var searchResults: [Song] = []
    var shouldThrowOnPlay: Error?
    var shouldThrowOnSearch: Error?
    var shouldThrowOnSkip: Error?
    var librarySongs: [Song] = []
    var shouldThrowOnFetch: Error?

    private var currentState: PlaybackState = .empty
    private var continuation: AsyncStream<PlaybackState>.Continuation?
    private var queuedSongs: [Song] = []
    private var currentIndex: Int = 0

    nonisolated var playbackStateStream: AsyncStream<PlaybackState> {
        AsyncStream { continuation in
            Task { await self.setContinuation(continuation) }
        }
    }

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
        queuedSongs = songs.shuffled()
        currentIndex = 0
        if queuedSongs.isEmpty {
            updateState(.empty)
        } else {
            updateState(.stopped)
        }
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
}
