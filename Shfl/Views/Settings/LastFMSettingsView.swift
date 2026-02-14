import SwiftUI

struct LastFMSettingsView: View {
    @Environment(\.lastFMTransport) private var transport

    @State private var isConnected = false
    @State private var username: String?
    @State private var isConnecting = false
    @State private var isRefreshing = false
    @State private var errorMessage: String?
    @State private var recentTracks: [LastFMRecentTrack] = []
    @State private var recentTracksState: RecentTracksState = .idle

    var body: some View {
        List {
            statusSection
            actionsSection
            recentTracksSection
            helpSection
        }
        .navigationTitle("Last.fm")
        .refreshable {
            await refreshActivity(showLoading: recentTracks.isEmpty)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await refreshActivity(showLoading: recentTracks.isEmpty) }
                } label: {
                    if isRefreshing {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(!isConnected || isConnecting || isRefreshing)
                .accessibilityLabel("Refresh Last.fm activity")
            }
        }
        .task {
            await syncConnectionStatusOnly()
            await refreshActivity(showLoading: true)
        }
    }

    private var statusSection: some View {
        Section("Status") {
            HStack(spacing: 12) {
                Image(systemName: isConnected ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundStyle(isConnected ? .green : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(isConnected ? "Connected" : "Not connected")
                        .font(.body.weight(.semibold))
                    Text(username ?? "Connect Last.fm to enable scrobbling")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

        }
    }

    private var actionsSection: some View {
        Section("Actions") {
            if isConnected {
                Button(role: .destructive) {
                    Task { await disconnect() }
                } label: {
                    Label("Disconnect", systemImage: "link.badge.minus")
                }
                .disabled(isConnecting || isRefreshing)
            } else {
                Button {
                    Task { await connect() }
                } label: {
                    HStack {
                        Label("Connect to Last.fm", systemImage: "link.badge.plus")
                        Spacer()
                        if isConnecting {
                            ProgressView()
                        }
                    }
                }
                .disabled(isConnecting)
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private var recentTracksSection: some View {
        Section("Recent Tracks") {
            if !isConnected {
                emptyHintRow(
                    title: "Connect Last.fm to see recent tracks",
                    subtitle: "You can verify real-time scrobbling activity here after connecting."
                )
            } else {
                switch recentTracksState {
                case .idle, .loading:
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Loading recent tracks...")
                            .foregroundStyle(.secondary)
                    }
                case .empty:
                    emptyHintRow(
                        title: "No recent scrobbles yet",
                        subtitle: "Play music for at least half the track duration to scrobble."
                    )
                    Button("Retry") {
                        Task { await refreshActivity(showLoading: true) }
                    }
                case .error:
                    emptyHintRow(
                        title: "Couldn’t load recent tracks",
                        subtitle: "Check your connection and try again."
                    )
                    Button("Retry") {
                        Task { await refreshActivity(showLoading: true) }
                    }
                case .loaded:
                    ForEach(recentTracks) { track in
                        RecentTrackRow(track: track)
                    }
                }
            }
        }
    }

    private var helpSection: some View {
        Section {
            Text("Shfl sends a now-playing update immediately, then scrobbles after at least half the track duration (up to 4 minutes).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func emptyHintRow(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.body.weight(.semibold))
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func syncConnectionStatusOnly() async {
        guard let transport else { return }
        if let session = await transport.storedSession() {
            isConnected = true
            username = session.username
        } else {
            isConnected = false
            username = nil
            recentTracks = []
            recentTracksState = .idle
        }
    }

    private func refreshActivity(showLoading: Bool) async {
        guard let transport else { return }
        guard !isRefreshing else { return }

        isRefreshing = true
        if showLoading {
            recentTracksState = .loading
        }

        await syncConnectionStatusOnly()

        guard isConnected else {
            isRefreshing = false
            return
        }

        do {
            let tracks = try await transport.fetchRecentTracks(limit: 20)
            recentTracks = tracks
            recentTracksState = tracks.isEmpty ? .empty : .loaded
            errorMessage = nil
        } catch {
            recentTracksState = .error
            errorMessage = "Couldn’t refresh Last.fm activity. Try again in a moment."
        }

        isRefreshing = false
    }

    @MainActor
    private func connect() async {
        guard let transport else { return }
        isConnecting = true
        errorMessage = nil

        do {
            let session = try await transport.authenticate()
            isConnected = true
            username = session.username
            await refreshActivity(showLoading: true)
        } catch LastFMAuthError.cancelled {
            // User cancelled intentionally.
        } catch let error as LastFMAuthError {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = "Failed to connect. Please try again."
        }

        isConnecting = false
    }

    private func disconnect() async {
        guard let transport else { return }
        do {
            try await transport.disconnect()
            isConnected = false
            username = nil
            recentTracks = []
            recentTracksState = .idle
            errorMessage = nil
        } catch {
            errorMessage = "Failed to disconnect."
        }
    }
}

private enum RecentTracksState: Equatable {
    case idle
    case loading
    case loaded
    case empty
    case error
}

private struct RecentTrackRow: View {
    let track: LastFMRecentTrack
    private static let playedAtFormat = Date.FormatStyle.dateTime
        .year()
        .month(.abbreviated)
        .day()
        .hour()
        .minute()

    var body: some View {
        HStack(spacing: 12) {
            artwork

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(track.title)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    if track.isNowPlaying {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }

                Text(track.artist)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if track.isNowPlaying {
                Text("Scrobbling now")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .multilineTextAlignment(.trailing)
            } else if let playedAt = track.playedAt {
                Text(playedAt, format: Self.playedAtFormat)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
            } else {
                Text("Just now")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(trackAccessibilityLabel)
    }

    @ViewBuilder
    private var artwork: some View {
        if let artworkURL = track.artworkURL {
            AsyncImage(url: artworkURL) { phase in
                switch phase {
                case .empty:
                    artworkPlaceholder
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    artworkPlaceholder
                @unknown default:
                    artworkPlaceholder
                }
            }
            .frame(width: 46, height: 46)
            .clipShape(.rect(cornerRadius: 8))
        } else {
            artworkPlaceholder
                .frame(width: 46, height: 46)
        }
    }

    private var artworkPlaceholder: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(.quaternary)
            .overlay {
                Image(systemName: "music.note")
                    .foregroundStyle(.secondary)
            }
    }

    private var trackAccessibilityLabel: String {
        if track.isNowPlaying {
            return "\(track.title), \(track.artist), scrobbling now"
        }
        if let playedAt = track.playedAt {
            let timestamp = playedAt.formatted(Self.playedAtFormat)
            return "\(track.title), \(track.artist), played at \(timestamp)"
        }
        return "\(track.title), \(track.artist)"
    }
}

#Preview {
    NavigationStack {
        LastFMSettingsView()
    }
}
