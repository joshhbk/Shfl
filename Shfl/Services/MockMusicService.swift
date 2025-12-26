import Foundation

/// Mock music service for development and testing when MusicKit is unavailable
final class MockMusicService: MusicService, @unchecked Sendable {
    private var currentState: PlaybackState = .empty
    private var continuation: AsyncStream<PlaybackState>.Continuation?
    private var queuedSongs: [Song] = []
    private var currentIndex: Int = 0

    private let mockSongs: [Song] = [
        Song(id: "1", title: "Bohemian Rhapsody", artist: "Queen", albumTitle: "A Night at the Opera", artworkURL: nil),
        Song(id: "2", title: "Stairway to Heaven", artist: "Led Zeppelin", albumTitle: "Led Zeppelin IV", artworkURL: nil),
        Song(id: "3", title: "Hotel California", artist: "Eagles", albumTitle: "Hotel California", artworkURL: nil),
        Song(id: "4", title: "Comfortably Numb", artist: "Pink Floyd", albumTitle: "The Wall", artworkURL: nil),
        Song(id: "5", title: "Sweet Child O' Mine", artist: "Guns N' Roses", albumTitle: "Appetite for Destruction", artworkURL: nil),
        Song(id: "6", title: "Back in Black", artist: "AC/DC", albumTitle: "Back in Black", artworkURL: nil),
        Song(id: "7", title: "Smells Like Teen Spirit", artist: "Nirvana", albumTitle: "Nevermind", artworkURL: nil),
        Song(id: "8", title: "Imagine", artist: "John Lennon", albumTitle: "Imagine", artworkURL: nil),
        Song(id: "9", title: "Purple Rain", artist: "Prince", albumTitle: "Purple Rain", artworkURL: nil),
        Song(id: "10", title: "Like a Rolling Stone", artist: "Bob Dylan", albumTitle: "Highway 61 Revisited", artworkURL: nil),
        Song(id: "11", title: "What's Going On", artist: "Marvin Gaye", albumTitle: "What's Going On", artworkURL: nil),
        Song(id: "12", title: "Respect", artist: "Aretha Franklin", albumTitle: "I Never Loved a Man", artworkURL: nil),
        Song(id: "13", title: "Good Vibrations", artist: "The Beach Boys", albumTitle: "Smiley Smile", artworkURL: nil),
        Song(id: "14", title: "Johnny B. Goode", artist: "Chuck Berry", albumTitle: "Chuck Berry Is on Top", artworkURL: nil),
        Song(id: "15", title: "Hey Jude", artist: "The Beatles", albumTitle: "Single", artworkURL: nil),
        Song(id: "16", title: "Superstition", artist: "Stevie Wonder", albumTitle: "Talking Book", artworkURL: nil),
        Song(id: "17", title: "Born to Run", artist: "Bruce Springsteen", albumTitle: "Born to Run", artworkURL: nil),
        Song(id: "18", title: "London Calling", artist: "The Clash", albumTitle: "London Calling", artworkURL: nil),
        Song(id: "19", title: "I Want to Hold Your Hand", artist: "The Beatles", albumTitle: "Meet The Beatles!", artworkURL: nil),
        Song(id: "20", title: "Billie Jean", artist: "Michael Jackson", albumTitle: "Thriller", artworkURL: nil),
    ]

    var playbackStateStream: AsyncStream<PlaybackState> {
        AsyncStream { [weak self] continuation in
            self?.continuation = continuation
            continuation.yield(self?.currentState ?? .empty)
        }
    }

    var isAuthorized: Bool {
        get async { true }
    }

    func requestAuthorization() async -> Bool {
        true
    }

    func fetchLibrarySongs(
        sortedBy: SortOption,
        limit: Int,
        offset: Int
    ) async throws -> LibraryPage {
        // Simulate network delay
        try await Task.sleep(nanoseconds: 300_000_000)

        let endIndex = min(offset + limit, mockSongs.count)
        let songs = offset < mockSongs.count ? Array(mockSongs[offset..<endIndex]) : []
        let hasMore = endIndex < mockSongs.count

        return LibraryPage(songs: songs, hasMore: hasMore)
    }

    func searchLibrarySongs(query: String) async throws -> [Song] {
        // Simulate network delay
        try await Task.sleep(nanoseconds: 300_000_000)

        let lowercasedQuery = query.lowercased()
        return mockSongs.filter {
            $0.title.lowercased().contains(lowercasedQuery) ||
            $0.artist.lowercased().contains(lowercasedQuery)
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
        guard !queuedSongs.isEmpty else { return }
        currentIndex = (currentIndex + 1) % queuedSongs.count
        let song = queuedSongs[currentIndex]
        updateState(.playing(song))
    }

    private func updateState(_ state: PlaybackState) {
        currentState = state
        continuation?.yield(state)
    }
}
