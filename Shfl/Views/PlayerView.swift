import SwiftUI

struct PlayerView: View {
    @ObservedObject var player: ShufflePlayer
    let onManageTapped: () -> Void

    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                backgroundGradient

                VStack(spacing: 0) {
                    // Error banner at top
                    if showError {
                        ErrorBanner(message: errorMessage) {
                            withAnimation {
                                showError = false
                            }
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    HStack {
                        Spacer()
                        CapacityIndicator(current: player.songCount, maximum: player.capacity)
                        Spacer()
                    }
                    .padding(.top, showError ? 16 : geometry.safeAreaInsets.top + 16)

                    Spacer()

                    VStack(spacing: 48) {
                        nowPlayingSection

                        controlsSection
                    }
                    .padding(.horizontal, 32)

                    Spacer()

                    Button(action: onManageTapped) {
                        Text("Manage Songs")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, geometry.safeAreaInsets.bottom + 24)
                }
            }
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.2), value: showError)
            .onChange(of: player.playbackState) { _, newState in
                if case .error(let error) = newState {
                    errorMessage = error.localizedDescription
                    withAnimation {
                        showError = true
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var nowPlayingSection: some View {
        switch player.playbackState {
        case .loading(let song):
            VStack(spacing: 12) {
                ProgressView()
                    .scaleEffect(1.2)
                NowPlayingInfo(title: song.title, artist: song.artist)
                    .opacity(0.7)
            }
            .transition(.opacity)
        case .playing(let song), .paused(let song):
            NowPlayingInfo(title: song.title, artist: song.artist)
                .transition(.opacity)
        default:
            emptyStateView
        }
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(white: 0.95),
                Color(white: 0.90)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Text("No songs yet")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)

            Text("Add some music to get started")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
    }

    private var controlsSection: some View {
        HStack(spacing: 40) {
            if player.songCount > 0 {
                SkipButton {
                    Task {
                        try? await player.skipToNext()
                    }
                }
            } else {
                Color.clear.frame(width: 56, height: 56)
            }

            PlayPauseButton(isPlaying: player.playbackState.isPlaying) {
                Task {
                    try? await player.togglePlayback()
                }
            }
            .disabled(player.songCount == 0)
            .opacity(player.songCount == 0 ? 0.5 : 1.0)

            Color.clear.frame(width: 56, height: 56)
        }
    }
}

private final class PreviewMockMusicService: MusicService, @unchecked Sendable {
    var isAuthorized: Bool { true }
    var playbackStateStream: AsyncStream<PlaybackState> {
        AsyncStream { continuation in
            continuation.yield(.empty)
        }
    }
    func requestAuthorization() async -> Bool { true }
    func searchLibrary(query: String) async throws -> [Song] { [] }
    func setQueue(songs: [Song]) async throws {}
    func play() async throws {}
    func pause() async {}
    func skipToNext() async throws {}
}

#Preview("Empty State") {
    let mockService = PreviewMockMusicService()
    let player = ShufflePlayer(musicService: mockService)
    return PlayerView(player: player, onManageTapped: {})
}

#Preview("Playing") {
    let mockService = PreviewMockMusicService()
    let player = ShufflePlayer(musicService: mockService)
    return PlayerView(player: player, onManageTapped: {})
}
