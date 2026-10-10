import Foundation
import Observation

/// What `LastFMAccount` needs from Last.fm. `LastFMTransport` is the live
/// one; tests supply their own.
package nonisolated protocol LastFMConnection: Sendable {
    /// The signed-in session, or nil when signed out.
    func storedSession() async -> LastFMSession?
    func fetchRecentTracks(limit: Int) async throws -> [LastFMRecentTrack]
    /// Where to send the listener to approve Shfl.
    func signIn() throws -> LastFMSignIn
    /// Finishes sign-in with the URL Last.fm redirected to.
    func completeSignIn(callbackURL: URL) async throws -> LastFMSession
    func disconnect() async throws
}

/// The listener's Last.fm connection as the settings screen shows it: whether
/// they're signed in, their recent scrobbles, and connecting or disconnecting.
@Observable
@MainActor
public final class LastFMAccount {
    /// Runs Last.fm's sign-in page in a web authentication session and returns
    /// the URL it redirects to, or nil when the listener backs out.
    public typealias WebSignIn = (_ signIn: LastFMSignIn) async throws -> URL?

    deinit {} // Keep nonisolated: Xcode 27 synthesizes an isolated one that can crash on release. See ViewTeardownTests.
    public private(set) var connectionState: ConnectionState = .disconnected
    public private(set) var isRefreshing = false
    public private(set) var errorMessage: String?
    public private(set) var recentTracksState: RecentTracksState = .idle

    @ObservationIgnored private let connection: (any LastFMConnection)?

    /// - Parameter connection: Nil for launches that don't talk to Last.fm;
    ///   the account then stays signed out and every action does nothing.
    package init(connection: (any LastFMConnection)?) {
        self.connection = connection
    }

    /// Signed out for good, for previews and view tests.
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

    /// Clears any earlier error, including one from a failed connect.
    public func refreshActivity(showLoading: Bool) async {
        guard connection != nil, !isRefreshing else { return }

        isRefreshing = true
        errorMessage = nil
        if showLoading {
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

    /// Signs in through `webSignIn`, then loads recent tracks.
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
