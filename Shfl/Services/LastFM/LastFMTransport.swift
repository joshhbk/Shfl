import Foundation
import Network

actor LastFMTransport: ScrobbleTransport {
    private let client: LastFMClient
    private let authenticator: LastFMAuthenticator
    private let queue: LastFMQueue
    private let networkMonitor: NWPathMonitor

    private var isNetworkAvailable = true
    private var hasStartedNetworkMonitoring = false
    private let maxFlushAttemptsPerCycle = 3
    private let flushRetryDelayNanoseconds: UInt64 = 5_000_000_000

    init(
        apiKey: String,
        sharedSecret: String,
        keychainService: String = "com.shfl.lastfm.session",
        queueURL: URL? = nil
    ) {
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
        guard await isAuthenticated, isNetworkAvailable else { return }

        // Now playing is best-effort, no queuing
        do {
            try await sendNowPlayingRequest(event)
        } catch {
            // Ignore errors for now playing
        }
    }

    func pendingScrobbles() async -> [ScrobbleEvent] {
        await queue.pending()
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

            do {
                for event in batch {
                    try await sendScrobble(event)
                }
                await queue.confirmDequeued(batch)
            } catch {
                await queue.returnToQueue(batch)
                attemptsRemaining -= 1
                guard attemptsRemaining > 0 else { break }
                try? await Task.sleep(nanoseconds: flushRetryDelayNanoseconds)
            }
        }
    }
}

enum LastFMError: Error {
    case requestFailed
    case apiError
}
