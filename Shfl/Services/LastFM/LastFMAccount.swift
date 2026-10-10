import Foundation
import Observation

enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case connected(username: String)

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    var isConnecting: Bool {
        if case .connecting = self { return true }
        return false
    }

    var username: String? {
        if case .connected(let name) = self { return name }
        return nil
    }
}

enum RecentTracksState: Equatable {
    case idle
    case loading
    case loaded([LastFMRecentTrack])
    case empty
    case error

    var tracks: [LastFMRecentTrack] {
        if case .loaded(let tracks) = self { return tracks }
        return []
    }

    var hasLoadedTracks: Bool {
        if case .loaded = self { return true }
        return false
    }
}

@Observable
@MainActor
final class LastFMAccount {
    /// nil means the listener backed out.
    typealias WebSignIn = (_ signIn: LastFMSignIn) async throws -> URL?

    deinit {} // Keep nonisolated: Xcode 27 synthesizes an isolated one that can crash on release. See ViewTeardownTests.
    var connectionState: ConnectionState = .disconnected
    var isRefreshing = false
    var errorMessage: String?
    var recentTracksState: RecentTracksState = .idle

    var transport: LastFMTransport?

    func syncConnectionStatusOnly() async {
        guard let transport else { return }
        if let session = await transport.storedSession() {
            connectionState = .connected(username: session.username)
        } else {
            connectionState = .disconnected
            recentTracksState = .idle
        }
    }

    func refreshActivity(showLoading: Bool) async {
        guard transport != nil else { return }
        guard !isRefreshing else { return }

        isRefreshing = true
        if showLoading {
            recentTracksState = .loading
        }

        await syncConnectionStatusOnly()

        guard connectionState.isConnected, let transport else {
            isRefreshing = false
            return
        }

        do {
            let tracks = try await transport.fetchRecentTracks(limit: 20)
            recentTracksState = tracks.isEmpty ? .empty : .loaded(tracks)
            errorMessage = nil
        } catch {
            recentTracksState = .error
            errorMessage = "Couldn't refresh Last.fm activity. Try again in a moment."
        }

        isRefreshing = false
    }

    func connect(using webSignIn: WebSignIn) async {
        guard let transport else { return }
        connectionState = .connecting
        errorMessage = nil

        do {
            guard let callbackURL = try await webSignIn(try transport.signIn()) else {
                connectionState = .disconnected
                return
            }
            let session = try await transport.completeSignIn(callbackURL: callbackURL)
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

    func disconnect() async {
        guard let transport else { return }
        do {
            try await transport.disconnect()
            connectionState = .disconnected
            recentTracksState = .idle
            errorMessage = nil
        } catch {
            errorMessage = "Failed to disconnect."
        }
    }
}
