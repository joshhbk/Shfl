import Foundation
import Network

nonisolated struct LastFMRecentTrack: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let artist: String
    let artworkURL: URL?
    let playedAt: Date?
    let isNowPlaying: Bool

    init(
        title: String,
        artist: String,
        artworkURL: URL?,
        playedAt: Date?,
        isNowPlaying: Bool
    ) {
        self.title = title
        self.artist = artist
        self.artworkURL = artworkURL
        self.playedAt = playedAt
        self.isNowPlaying = isNowPlaying
        let playedTimestamp = playedAt.map { String(Int($0.timeIntervalSince1970)) } ?? "now"
        self.id = "\(title)|\(artist)|\(playedTimestamp)|\(isNowPlaying)"
    }
}

nonisolated enum LastFMNowPlayingQueueReason: Equatable, Sendable {
    case disconnected
    case offline
}

nonisolated enum LastFMNowPlayingState: Equatable, Sendable {
    case idle
    case scrobblingNow(ScrobbleEvent, updatedAt: Date)
    case queued(ScrobbleEvent, reason: LastFMNowPlayingQueueReason, updatedAt: Date)
    case failed(ScrobbleEvent, updatedAt: Date)
}

actor LastFMTransport: ScrobbleTransport {
    private let apiKey: String
    private let client: LastFMClient
    private let authenticator: LastFMAuthenticator
    private let queue: LastFMQueue
    private let networkMonitor: NWPathMonitor

    private var isNetworkAvailable = true
    private var hasStartedNetworkMonitoring = false
    private let maxFlushAttemptsPerCycle = 3
    private let flushRetryDelayNanoseconds: UInt64 = 5_000_000_000
    private var nowPlayingState: LastFMNowPlayingState = .idle

    init(
        apiKey: String,
        sharedSecret: String,
        keychainService: String = "com.shfl.lastfm.session",
        queueURL: URL? = nil
    ) {
        self.apiKey = apiKey
        self.client = LastFMClient(apiKey: apiKey, sharedSecret: sharedSecret)
        self.authenticator = LastFMAuthenticator(
            apiKey: apiKey,
            sharedSecret: sharedSecret,
            keychainService: keychainService
        )
        self.queue = LastFMQueue(storageURL: queueURL)
        self.networkMonitor = NWPathMonitor()

        Task { [weak self] in
            await self?.startNetworkMonitoringIfNeeded()
        }
    }

    var isAuthenticated: Bool {
        get async {
            await authenticator.isAuthenticated
        }
    }

    func scrobble(_ event: ScrobbleEvent) async {
        guard await isAuthenticated else {
            await queue.enqueue(event)
            return
        }

        if isNetworkAvailable {
            do {
                try await sendScrobble(event)
            } catch {
                await queue.enqueue(event)
            }
        } else {
            await queue.enqueue(event)
        }
    }

    func sendNowPlaying(_ event: ScrobbleEvent) async {
        guard await isAuthenticated else {
            nowPlayingState = .queued(event, reason: .disconnected, updatedAt: Date())
            return
        }

        guard isNetworkAvailable else {
            nowPlayingState = .queued(event, reason: .offline, updatedAt: Date())
            return
        }

        do {
            try await sendNowPlayingRequest(event)
            nowPlayingState = .scrobblingNow(event, updatedAt: Date())
        } catch {
            nowPlayingState = .failed(event, updatedAt: Date())
        }
    }

    func pendingScrobbles() async -> [ScrobbleEvent] {
        await queue.pending()
    }

    func currentNowPlayingState() -> LastFMNowPlayingState {
        nowPlayingState
    }

    func fetchRecentTracks(limit: Int = 20) async throws -> [LastFMRecentTrack] {
        guard let session = await authenticator.storedSession() else { return [] }

        var components = URLComponents(string: "https://ws.audioscrobbler.com/2.0/")
        components?.queryItems = [
            URLQueryItem(name: "method", value: "user.getrecenttracks"),
            URLQueryItem(name: "user", value: session.username),
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "limit", value: String(max(limit, 1)))
        ]

        guard let url = components?.url else {
            throw LastFMError.requestFailed
        }

        let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url))
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw LastFMError.requestFailed
        }

        if Self.containsAPIError(data) {
            throw LastFMError.apiError
        }

        return try Self.decodeRecentTracks(from: data, limit: limit)
    }

    nonisolated static func decodeRecentTracks(from data: Data, limit: Int) throws -> [LastFMRecentTrack] {
        let response = try JSONDecoder().decode(LastFMRecentTracksResponse.self, from: data)
        return response.recenttracks.track.prefix(max(limit, 1)).map { track in
            let nowPlaying = track.attributes?.nowplaying == "true"
            let timestamp = track.date?.uts.flatMap(TimeInterval.init).map(Date.init(timeIntervalSince1970:))
            return LastFMRecentTrack(
                title: track.name,
                artist: track.artist.text,
                artworkURL: preferredArtworkURL(from: track.image),
                playedAt: timestamp,
                isNowPlaying: nowPlaying
            )
        }
    }

    // MARK: - Authentication

    @MainActor
    func authenticate() async throws -> LastFMSession {
        let session = try await authenticator.authenticate()
        await client.setSessionKey(session.sessionKey)
        await flushQueue()
        return session
    }

    func storedSession() async -> LastFMSession? {
        await authenticator.storedSession()
    }

    func disconnect() async throws {
        try await authenticator.clearSession()
        nowPlayingState = .idle
    }

    func shutdown() {
        networkMonitor.cancel()
    }

    // MARK: - Private

    private func startNetworkMonitoringIfNeeded() {
        guard !hasStartedNetworkMonitoring else { return }
        hasStartedNetworkMonitoring = true

        networkMonitor.pathUpdateHandler = { [weak self] path in
            Task { [weak self] in
                guard let self = self else { return }
                let wasAvailable = await self.isNetworkAvailable
                await self.setNetworkAvailable(path.status == .satisfied)

                if !wasAvailable && path.status == .satisfied {
                    await self.flushQueue()
                }
            }
        }
        networkMonitor.start(queue: .global(qos: .utility))
    }

    private func setNetworkAvailable(_ available: Bool) {
        isNetworkAvailable = available
    }

    private func sendScrobble(_ event: ScrobbleEvent) async throws {
        guard let session = await authenticator.storedSession() else { return }
        await client.setSessionKey(session.sessionKey)

        let request = await client.buildScrobbleRequest(event)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw LastFMError.requestFailed
        }

        // Check for API error in response
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           json["error"] != nil {
            throw LastFMError.apiError
        }
    }

    private func sendNowPlayingRequest(_ event: ScrobbleEvent) async throws {
        guard let session = await authenticator.storedSession() else { return }
        await client.setSessionKey(session.sessionKey)

        let request = await client.buildNowPlayingRequest(event)
        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw LastFMError.requestFailed
        }
    }

    private func flushQueue() async {
        guard await isAuthenticated, isNetworkAvailable else { return }

        var attemptsRemaining = maxFlushAttemptsPerCycle

        while attemptsRemaining > 0 {
            let batch = await queue.dequeueBatch(limit: 50)
            guard !batch.isEmpty else { break }

            var sent: [ScrobbleEvent] = []
            var didFail = false

            for (index, event) in batch.enumerated() {
                do {
                    try await sendScrobble(event)
                    sent.append(event)
                } catch {
                    let unsent = Array(batch[index...])

                    if !sent.isEmpty {
                        await queue.confirmDequeued(sent)
                    }

                    await queue.returnToQueue(unsent)
                    didFail = true
                    attemptsRemaining -= 1
                    guard attemptsRemaining > 0 else { break }
                    try? await Task.sleep(nanoseconds: flushRetryDelayNanoseconds)
                    break
                }
            }

            if !didFail {
                await queue.confirmDequeued(batch)
            }
        }
    }

    private nonisolated static func containsAPIError(_ data: Data) -> Bool {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        return json["error"] != nil
    }

    private nonisolated static func preferredArtworkURL(from images: [LastFMRecentTracksResponse.RecentTrackImage]) -> URL? {
        let preferredSizes = ["extralarge", "large", "medium", "small"]

        for size in preferredSizes {
            if let value = images.first(where: { $0.size == size })?.text,
               !value.isEmpty,
               let url = URL(string: value) {
                return url
            }
        }

        if let fallback = images.first(where: { !$0.text.isEmpty })?.text {
            return URL(string: fallback)
        }

        return nil
    }
}

private nonisolated struct LastFMRecentTracksResponse: Decodable {
    let recenttracks: RecentTracks

    nonisolated struct RecentTracks: Decodable {
        let track: [RecentTrack]
    }

    nonisolated struct RecentTrack: Decodable {
        let name: String
        let artist: TextValue
        let image: [RecentTrackImage]
        let date: RecentTrackDate?
        let attributes: RecentTrackAttributes?

        enum CodingKeys: String, CodingKey {
            case name
            case artist
            case image
            case date
            case attributes = "@attr"
        }
    }

    nonisolated struct TextValue: Decodable {
        let text: String

        enum CodingKeys: String, CodingKey {
            case text = "#text"
        }

        init(from decoder: Decoder) throws {
            if let singleValue = try? decoder.singleValueContainer().decode(String.self) {
                self.text = singleValue
                return
            }

            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        }
    }

    nonisolated struct RecentTrackImage: Decodable {
        let text: String
        let size: String

        enum CodingKeys: String, CodingKey {
            case text = "#text"
            case size
        }
    }

    nonisolated struct RecentTrackDate: Decodable {
        let uts: String?
    }

    nonisolated struct RecentTrackAttributes: Decodable {
        let nowplaying: String?
    }
}

nonisolated enum LastFMError: Error {
    case requestFailed
    case apiError
}
