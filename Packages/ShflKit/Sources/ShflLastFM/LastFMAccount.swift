import Foundation
import Observation

package nonisolated protocol LastFMConnection: Sendable {
    func storedSession() async -> LastFMSession?
    func fetchRecentTracks(limit: Int) async throws -> [LastFMRecentTrack]
    func signIn() throws -> LastFMSignIn
    func completeSignIn(callbackURL: URL) async throws -> LastFMSession
    func disconnect() async throws
}

@Observable
@MainActor
public final class LastFMAccount {
    /// nil means the listener backed out.
    public typealias WebSignIn = (_ signIn: LastFMSignIn) async throws -> URL?

    deinit {} // Keep nonisolated: Xcode 27 synthesizes an isolated one that can crash on release. See ViewTeardownTests.
    public private(set) var connectionState: ConnectionState = .disconnected
    public private(set) var isRefreshing = false
    public private(set) var errorMessage: String?
    public private(set) var recentTracksState: RecentTracksState = .idle

    @ObservationIgnored private let connection: (any LastFMConnection)?

    package init(connection: (any LastFMConnection)?) {
        self.connection = connection
    }

    public static func preview() -> LastFMAccount {
        LastFMAccount(connection: nil)
    }

    public func syncConnectionStatusOnly() async {
        guard let connection else { return }
        if let session = await connection.storedSession() {
            connectionState = .connected(username: session.username)
        } else {
            connectionState = .disconnected
            recentTracksState = .idle
        }
    }

    /// By default the loading state shows only when no tracks have loaded yet.
    public func refreshActivity(showLoading: Bool? = nil) async {
        guard connection != nil, !isRefreshing else { return }

        isRefreshing = true
        errorMessage = nil
        if showLoading ?? !recentTracksState.hasLoadedTracks {
            recentTracksState = .loading
        }

        await syncConnectionStatusOnly()

        guard connectionState.isConnected, let connection else {
            isRefreshing = false
            return
        }

        do {
            let tracks = try await connection.fetchRecentTracks(limit: 20)
            recentTracksState = tracks.isEmpty ? .empty : .loaded(tracks)
            errorMessage = nil
        } catch {
            recentTracksState = .error
            errorMessage = "Couldn't refresh Last.fm activity. Try again in a moment."
        }

        isRefreshing = false
    }

    public func connect(using webSignIn: WebSignIn) async {
        guard let connection else { return }
        connectionState = .connecting
        errorMessage = nil

        do {
            guard let callbackURL = try await webSignIn(try connection.signIn()) else {
                connectionState = .disconnected
                return
            }
            let session = try await connection.completeSignIn(callbackURL: callbackURL)
            connectionState = .connected(username: session.username)
            await refreshActivity(showLoading: true)
        } catch let error as LastFMAuthError {
            connectionState = .disconnected
            errorMessage = error.localizedDescription
        } catch {
            connectionState = .disconnected
            errorMessage = "Failed to connect. Please try again."
        }
    }

    public func disconnect() async {
        guard let connection else { return }
        do {
            try await connection.disconnect()
            connectionState = .disconnected
            recentTracksState = .idle
            errorMessage = nil
        } catch {
            errorMessage = "Failed to disconnect."
        }
    }
}

extension LastFMAccount {
    public enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected(username: String)

        public var isConnected: Bool {
            if case .connected = self { return true }
            return false
        }

        public var isConnecting: Bool {
            if case .connecting = self { return true }
            return false
        }

        public var username: String? {
            if case .connected(let name) = self { return name }
            return nil
        }
    }

    public enum RecentTracksState: Equatable {
        case idle
        case loading
        case loaded([LastFMRecentTrack])
        case empty
        case error

        public var tracks: [LastFMRecentTrack] {
            if case .loaded(let tracks) = self { return tracks }
            return []
        }

        public var hasLoadedTracks: Bool {
            if case .loaded = self { return true }
            return false
        }
    }
}
