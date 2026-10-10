import AuthenticationServices
import ShflLastFM
import SwiftUI

struct LastFMSettingsTab: View {
    @Environment(LastFMAccount.self) private var account

    var body: some View {
        Form {
            Section {
                LastFMConnectionRow()
            } footer: {
                Text("Shuffled scrobbles a song once you've heard half of it, or four minutes.")
                    .foregroundStyle(.secondary)
            }
            if account.connectionState.isConnected {
                Section("Recent Tracks") {
                    LastFMRecentTracks()
                }
            }
        }
        .formStyle(.grouped)
        .task {
            await account.refreshActivity(showLoading: !account.recentTracksState.hasLoadedTracks)
        }
    }
}

private struct LastFMConnectionRow: View {
    @Environment(LastFMAccount.self) private var account
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession

    var body: some View {
        LabeledContent {
            switch account.connectionState {
            case .connected:
                Button("Disconnect", role: .destructive) {
                    Task { await account.disconnect() }
                }
                .accessibilityIdentifier("mac.settings.lastfm.disconnect")
            case .connecting:
                ProgressView().controlSize(.small)
            case .disconnected:
                Button("Connect") {
                    Task { await account.connect(using: runWebSignIn) }
                }
                .accessibilityIdentifier("mac.settings.lastfm.connect")
            }
        } label: {
            Text(account.connectionState.username.map { "Connected as \($0)" } ?? "Not connected")
            if let errorMessage = account.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }
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

private struct LastFMRecentTracks: View {
    @Environment(LastFMAccount.self) private var account

    var body: some View {
        switch account.recentTracksState {
        case .idle, .loading:
            ProgressView().controlSize(.small)
        case .empty:
            Text("No recent scrobbles yet.").foregroundStyle(.secondary)
        case .error:
            Button("Couldn't load recent tracks. Retry") {
                Task { await account.refreshActivity(showLoading: true) }
            }
        case .loaded(let tracks):
            ForEach(tracks) { track in
                LabeledContent(track.title, value: track.isNowPlaying ? "Now playing" : track.artist)
            }
        }
    }
}
