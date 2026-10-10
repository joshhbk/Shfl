import AuthenticationServices
import ShflLastFM
import SwiftUI

// Form rows get values and actions, not environment objects: rows AppKit builds for accessibility lack the environment.
struct LastFMSettingsTab: View {
    @Environment(LastFMAccount.self) private var account
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession

    var body: some View {
        Form {
            Section {
                LastFMConnectionRow(
                    connectionState: account.connectionState,
                    errorMessage: account.errorMessage,
                    connect: { Task { await account.connect(using: runWebSignIn) } },
                    disconnect: { Task { await account.disconnect() } }
                )
            } footer: {
                Text("Shuffled scrobbles a song once you've heard half of it, or four minutes.")
                    .foregroundStyle(.secondary)
            }
            if account.connectionState.isConnected {
                Section("Recent Tracks") {
                    LastFMRecentTracks(
                        state: account.recentTracksState,
                        retry: { Task { await account.refreshActivity(showLoading: true) } }
                    )
                }
            }
        }
        .formStyle(.grouped)
        .task {
            await account.refreshActivity()
        }
    }

    private func runWebSignIn(_ signIn: LastFMSignIn) async throws -> URL? {
        do {
            return try await webAuthenticationSession.authenticate(
                using: signIn.url,
                callbackURLScheme: signIn.callbackURLScheme,
                preferredBrowserSession: .shared
            )
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            return nil
        }
    }
}

private struct LastFMConnectionRow: View {
    let connectionState: LastFMAccount.ConnectionState
    let errorMessage: String?
    let connect: () -> Void
    let disconnect: () -> Void

    var body: some View {
        LabeledContent {
            switch connectionState {
            case .connected:
                Button("Disconnect", role: .destructive, action: disconnect)
                    .accessibilityIdentifier("mac.settings.lastfm.disconnect")
            case .connecting:
                ProgressView().controlSize(.small)
            case .disconnected:
                Button("Connect", action: connect)
                    .accessibilityIdentifier("mac.settings.lastfm.connect")
            }
        } label: {
            Text(connectionState.username.map { "Connected as \($0)" } ?? "Not connected")
            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }
        }
    }
}

private struct LastFMRecentTracks: View {
    let state: LastFMAccount.RecentTracksState
    let retry: () -> Void

    var body: some View {
        switch state {
        case .idle, .loading:
            ProgressView().controlSize(.small)
        case .empty:
            Text("No recent scrobbles yet.").foregroundStyle(.secondary)
        case .error:
            Button("Couldn't load recent tracks. Retry", action: retry)
        case .loaded(let tracks):
            ForEach(tracks) { track in
                LabeledContent(track.title, value: track.isNowPlaying ? "Now playing" : track.artist)
            }
        }
    }
}
