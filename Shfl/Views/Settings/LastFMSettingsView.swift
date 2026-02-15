import SwiftUI

struct LastFMSettingsView: View {
    @Environment(\.lastFMTransport) private var transport
    @State private var viewModel = LastFMSettingsViewModel()

    var body: some View {
        List {
            statusSection
            actionsSection
            recentTracksSection
            helpSection
        }
        .navigationTitle("Last.fm")
        .refreshable {
            await viewModel.refreshActivity(showLoading: !viewModel.recentTracksState.hasLoadedTracks)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await viewModel.refreshActivity(showLoading: !viewModel.recentTracksState.hasLoadedTracks) }
                } label: {
                    if viewModel.isRefreshing {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(!viewModel.connectionState.isConnected || viewModel.connectionState.isConnecting || viewModel.isRefreshing)
                .accessibilityLabel("Refresh Last.fm activity")
            }
        }
        .task {
            viewModel.transport = transport
            await viewModel.syncConnectionStatusOnly()
            await viewModel.refreshActivity(showLoading: true)
        }
    }

    private var statusSection: some View {
        Section("Status") {
            HStack(spacing: 12) {
                Image(systemName: viewModel.connectionState.isConnected ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundStyle(viewModel.connectionState.isConnected ? .green : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.connectionState.isConnected ? "Connected" : "Not connected")
                        .font(.body.weight(.semibold))
                    Text(viewModel.connectionState.username ?? "Connect Last.fm to enable scrobbling")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

        }
    }

    private var actionsSection: some View {
        Section("Actions") {
            switch viewModel.connectionState {
            case .connected:
                Button(role: .destructive) {
                    Task { await viewModel.disconnect() }
                } label: {
                    Label("Disconnect", systemImage: "link.badge.minus")
                }
                .disabled(viewModel.isRefreshing)
            case .connecting:
                Button {} label: {
                    HStack {
                        Label("Connect to Last.fm", systemImage: "link.badge.plus")
                        Spacer()
                        ProgressView()
                    }
                }
                .disabled(true)
            case .disconnected:
                Button {
                    Task { await viewModel.connect() }
                } label: {
                    Label("Connect to Last.fm", systemImage: "link.badge.plus")
                }
            }

            if let errorMessage = viewModel.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private var recentTracksSection: some View {
        Section("Recent Tracks") {
            if !viewModel.connectionState.isConnected {
                emptyHintRow(
                    title: "Connect Last.fm to see recent tracks",
                    subtitle: "You can verify real-time scrobbling activity here after connecting."
                )
            } else {
                switch viewModel.recentTracksState {
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
                        Task { await viewModel.refreshActivity(showLoading: true) }
                    }
                case .error:
                    emptyHintRow(
                        title: "Couldn't load recent tracks",
                        subtitle: "Check your connection and try again."
                    )
                    Button("Retry") {
                        Task { await viewModel.refreshActivity(showLoading: true) }
                    }
                case .loaded(let tracks):
                    ForEach(tracks) { track in
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
