import SwiftUI

struct PlayerView: View {
    @ObservedObject var player: ShufflePlayer
    let musicService: MusicService
    let onManageTapped: () -> Void
    let onAddTapped: () -> Void
    let onSettingsTapped: () -> Void

    @Environment(\.motionManager) private var motionManager
    @StateObject private var colorExtractor = AlbumArtColorExtractor()
    @State private var highlightOffset: CGPoint = .zero
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var currentTime: TimeInterval = 0
    @State private var duration: TimeInterval = 0
    @State private var progressTimer: Timer?
    @State private var currentThemeIndex: Int = Int.random(in: 0..<ShuffleTheme.allThemes.count)
    @State private var dragOffset: CGFloat = 0

    private var currentTheme: ShuffleTheme {
        ShuffleTheme.allThemes[currentThemeIndex]
    }

    /// Dynamic highlight color from album art, with fallback to theme-based color
    private var dynamicHighlightColor: Color {
        // Use extracted color if available
        if let extractedColor = colorExtractor.extractedColor {
            return extractedColor
        }
        // Fall back to theme-based color (white for colored themes, black for silver)
        return currentTheme.wheelStyle == .dark ? .black : .white
    }

    private let swipeThreshold: CGFloat = 100

    init(
        player: ShufflePlayer,
        musicService: MusicService,
        onManageTapped: @escaping () -> Void,
        onAddTapped: @escaping () -> Void = {},
        onSettingsTapped: @escaping () -> Void = {}
    ) {
        self.player = player
        self.musicService = musicService
        self.onManageTapped = onManageTapped
        self.onAddTapped = onAddTapped
        self.onSettingsTapped = onSettingsTapped
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background - first in ZStack = behind
                BrushedMetalBackground(
                    baseColor: currentTheme.bodyGradientTop,
                    intensity: currentTheme.brushedMetalIntensity,
                    highlightOffset: highlightOffset,
                    motionEnabled: currentTheme.motionEnabled,
                    highlightColor: dynamicHighlightColor
                )
                .animation(.easeInOut(duration: 0.5), value: colorExtractor.extractedColor?.description)

                // Content
                VStack(spacing: 0) {
                    if showError {
                        ErrorBanner(message: errorMessage) {
                            withAnimation {
                                showError = false
                            }
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    topBar(geometry: geometry)

                    Spacer()

                    VStack(spacing: 32) {
                        nowPlayingSection

                        ClickWheelView(
                            isPlaying: player.playbackState.isPlaying,
                            onPlayPause: handlePlayPause,
                            onSkipForward: handleSkipForward,
                            onSkipBack: handleSkipBack,
                            onVolumeUp: { VolumeController.increaseVolume() },
                            onVolumeDown: { VolumeController.decreaseVolume() }
                        )
                        .disabled(player.songCount == 0)
                        .opacity(player.songCount == 0 ? 0.6 : 1.0)

                        if FeatureFlags.showProgressBar {
                            PlaybackProgressBar(
                                currentTime: currentTime,
                                duration: duration
                            )
                            .padding(.horizontal, 40)
                        }
                    }

                    Spacer()

                    Button(action: onManageTapped) {
                        Text("View Library")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(currentTheme.secondaryTextColor)
                    }
                    .padding(.bottom, geometry.safeAreaInsets.bottom + 24)
                }

            }
            .ignoresSafeArea()
            .simultaneousGesture(themeSwipeGesture)
            .animation(.easeInOut(duration: 0.2), value: showError)
            .environment(\.shuffleTheme, currentTheme)
            .onChange(of: player.playbackState) { _, newState in
                handlePlaybackStateChange(newState)
            }
            .onAppear {
                startProgressTimer()
                motionManager?.start()
                // Extract color if there's already a song playing
                if let song = player.playbackState.currentSong {
                    colorExtractor.updateColor(for: song.id)
                }
            }
            .onDisappear {
                stopProgressTimer()
                motionManager?.stop()
            }
            .onChange(of: motionManager?.pitch) { _, _ in
                updateHighlightOffset()
            }
            .onChange(of: motionManager?.roll) { _, _ in
                updateHighlightOffset()
            }
        }
    }

    @ViewBuilder
    private func topBar(geometry: GeometryProxy) -> some View {
        HStack {
            Button(action: onAddTapped) {
                HStack(spacing: 4) {
                    Text("Songs")
                        .font(.system(size: 16, weight: .medium))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(currentTheme.textColor)
            }
            Spacer()
            Button(action: onSettingsTapped) {
                Image(systemName: "gearshape")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(currentTheme.textColor)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, showError ? 16 : geometry.safeAreaInsets.top + 16)
    }

    @ViewBuilder
    private var nowPlayingSection: some View {
        switch player.playbackState {
        case .loading(let song):
            VStack(spacing: 12) {
                ProgressView()
                    .scaleEffect(1.2)
                    .tint(currentTheme.textColor)
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

    private var themeSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 30)
            .onChanged { value in
                let translation = value.translation.width
                // Add rubber-band resistance at edges
                if (currentThemeIndex == 0 && translation > 0) ||
                   (currentThemeIndex == ShuffleTheme.allThemes.count - 1 && translation < 0) {
                    dragOffset = translation * 0.3 // Resistance
                } else {
                    dragOffset = translation
                }
            }
            .onEnded { value in
                let translation = value.translation.width
                let velocity = value.predictedEndTranslation.width

                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                    if translation < -swipeThreshold || velocity < -500 {
                        // Swipe left - next theme
                        if currentThemeIndex < ShuffleTheme.allThemes.count - 1 {
                            currentThemeIndex += 1
                            HapticFeedback.light.trigger()
                        } else {
                            HapticFeedback.light.trigger() // Boundary bump
                        }
                    } else if translation > swipeThreshold || velocity > 500 {
                        // Swipe right - previous theme
                        if currentThemeIndex > 0 {
                            currentThemeIndex -= 1
                            HapticFeedback.light.trigger()
                        } else {
                            HapticFeedback.light.trigger() // Boundary bump
                        }
                    }
                    dragOffset = 0
                }
            }
    }

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Text("No songs yet")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(currentTheme.textColor)

            Text("Add some music to get started")
                .font(.system(size: 14))
                .foregroundStyle(currentTheme.secondaryTextColor)
        }
    }

    // MARK: - Actions

    private func handlePlayPause() {
        Task {
            try? await player.togglePlayback()
        }
    }

    private func handleSkipForward() {
        Task {
            try? await player.skipToNext()
        }
    }

    private func handleSkipBack() {
        Task {
            try? await player.restartOrSkipToPrevious()
        }
    }

    private func handlePlaybackStateChange(_ newState: PlaybackState) {
        if case .error(let error) = newState {
            errorMessage = error.localizedDescription
            withAnimation {
                showError = true
            }
        }

        // Update duration when song changes
        duration = musicService.currentSongDuration

        // Extract color from album artwork
        if let song = newState.currentSong {
            colorExtractor.updateColor(for: song.id)
        } else {
            colorExtractor.clear()
        }
    }

    // MARK: - Progress Timer

    private func startProgressTimer() {
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            currentTime = musicService.currentPlaybackTime
            duration = musicService.currentSongDuration
        }
    }

    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    // MARK: - Motion

    private func updateHighlightOffset() {
        guard let manager = motionManager else { return }
        highlightOffset = MotionManager.highlightOffset(
            pitch: manager.pitch,
            roll: manager.roll,
            sensitivity: currentTheme.motionSensitivity,
            maxOffset: 220
        )
    }
}

private final class PreviewMockMusicService: MusicService, @unchecked Sendable {
    var isAuthorized: Bool { true }
    var currentPlaybackTime: TimeInterval { 78 }
    var currentSongDuration: TimeInterval { 242 }
    var playbackStateStream: AsyncStream<PlaybackState> {
        AsyncStream { continuation in
            continuation.yield(.empty)
        }
    }
    func requestAuthorization() async -> Bool { true }
    func prefetchLibrary() async {}
    func fetchLibrarySongs(sortedBy: SortOption, limit: Int, offset: Int) async throws -> LibraryPage {
        LibraryPage(songs: [], hasMore: false)
    }
    func searchLibrarySongs(query: String) async throws -> [Song] { [] }
    func setQueue(songs: [Song]) async throws {}
    func play() async throws {}
    func pause() async {}
    func skipToNext() async throws {}
    func skipToPrevious() async throws {}
    func restartOrSkipToPrevious() async throws {}
}

#Preview("Empty State") {
    let mockService = PreviewMockMusicService()
    let player = ShufflePlayer(musicService: mockService)
    return PlayerView(
        player: player,
        musicService: mockService,
        onManageTapped: {},
        onAddTapped: {},
        onSettingsTapped: {}
    )
}

#Preview("Playing") {
    let mockService = PreviewMockMusicService()
    let player = ShufflePlayer(musicService: mockService)
    return PlayerView(
        player: player,
        musicService: mockService,
        onManageTapped: {},
        onAddTapped: {},
        onSettingsTapped: {}
    )
}
