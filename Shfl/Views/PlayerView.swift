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
                // Background - album art with minimal blur
                AlbumArtBackground(
                    artworkURL: player.playbackState.currentSong?.artworkURL,
                    fallbackColor: currentTheme.bodyGradientTop,
                    blurRadius: 3
                )

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

                    // Song info panel - brushed metal
                    ShuffleBodyView(highlightOffset: highlightOffset, height: 120) {
                        songInfoContent
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .padding(.horizontal, 20)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)

                    // Controls panel - brushed metal
                    ShuffleBodyView(highlightOffset: highlightOffset) {
                        ClickWheelView(
                            isPlaying: player.playbackState.isPlaying,
                            onPlayPause: handlePlayPause,
                            onSkipForward: handleSkipForward,
                            onSkipBack: handleSkipBack,
                            onVolumeUp: { VolumeController.increaseVolume() },
                            onVolumeDown: { VolumeController.decreaseVolume() },
                            highlightOffset: highlightOffset,
                            scale: 0.6
                        )
                        .disabled(player.songCount == 0)
                        .opacity(player.songCount == 0 ? 0.6 : 1.0)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, geometry.safeAreaInsets.bottom + 12)
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
                Image(systemName: "music.note.list")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(currentTheme.bodyGradientTop)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .strokeBorder(.white.opacity(0.3), lineWidth: 1)
                    )
            }
            Spacer()
            Button(action: onSettingsTapped) {
                Image(systemName: "gearshape")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(currentTheme.bodyGradientTop)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .strokeBorder(.white.opacity(0.3), lineWidth: 1)
                    )
            }
        }
        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
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

    @ViewBuilder
    private var songInfoContent: some View {
        switch player.playbackState {
        case .loading(let song):
            VStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.8)
                    .tint(currentTheme.textColor)
                Text(song.title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(currentTheme.textColor)
                    .lineLimit(1)
                Text(song.artist)
                    .font(.system(size: 14))
                    .foregroundStyle(currentTheme.secondaryTextColor)
                    .lineLimit(1)
            }
        case .playing(let song), .paused(let song):
            VStack(spacing: 4) {
                Text(song.title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(currentTheme.textColor)
                    .lineLimit(1)
                Text(song.artist)
                    .font(.system(size: 14))
                    .foregroundStyle(currentTheme.secondaryTextColor)
                    .lineLimit(1)

                if FeatureFlags.showProgressBar {
                    PlaybackProgressBar(
                        currentTime: currentTime,
                        duration: duration
                    )
                    .padding(.top, 8)
                }
            }
        default:
            VStack(spacing: 8) {
                Text("No songs yet")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(currentTheme.textColor)
                Text("Add some music to get started")
                    .font(.system(size: 14))
                    .foregroundStyle(currentTheme.secondaryTextColor)
            }
        }
    }

    @ViewBuilder
    private var songInfoPanel: some View {
        switch player.playbackState {
        case .loading(let song):
            FrostedPanel {
                VStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(.white)
                    Text(song.title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(song.artist)
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }
            .transition(.opacity)
        case .playing(let song), .paused(let song):
            FrostedPanel {
                VStack(spacing: 4) {
                    Text(song.title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(song.artist)
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)

                    if FeatureFlags.showProgressBar {
                        PlaybackProgressBar(
                            currentTime: currentTime,
                            duration: duration
                        )
                        .padding(.top, 8)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .padding(.horizontal, 8)
            }
            .transition(.opacity)
        default:
            FrostedPanel {
                VStack(spacing: 8) {
                    Text("No songs yet")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Add some music to get started")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.7))
                    Button(action: onAddTapped) {
                        Text("Add Songs")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            .background(.white.opacity(0.2))
                            .clipShape(Capsule())
                    }
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }
        }
    }

    @ViewBuilder
    private var overlayNowPlayingSection: some View {
        switch player.playbackState {
        case .loading(let song):
            VStack(spacing: 12) {
                ProgressView()
                    .scaleEffect(1.2)
                    .tint(.white)
                OverlaySongInfo(title: song.title, artist: song.artist)
                    .opacity(0.7)
            }
            .transition(.opacity)
        case .playing(let song), .paused(let song):
            OverlaySongInfo(title: song.title, artist: song.artist)
                .transition(.opacity)
        default:
            overlayEmptyStateView
        }
    }

    private var overlayEmptyStateView: some View {
        VStack(spacing: 8) {
            Text("No songs yet")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)

            Text("Add some music to get started")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.7))
        }
        .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
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
    let initialState: PlaybackState

    init(initialState: PlaybackState = .empty) {
        self.initialState = initialState
    }

    var isAuthorized: Bool { true }
    var currentPlaybackTime: TimeInterval { 78 }
    var currentSongDuration: TimeInterval { 242 }
    var playbackStateStream: AsyncStream<PlaybackState> {
        let state = initialState
        return AsyncStream { continuation in
            continuation.yield(state)
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

private let previewSong = Song(
    id: "preview-1",
    title: "Bohemian Rhapsody",
    artist: "Queen",
    albumTitle: "A Night at the Opera",
    artworkURL: URL(string: "https://is1-ssl.mzstatic.com/image/thumb/Music115/v4/3c/1b/a9/3c1ba9e1-cf27-f6d1-6287-a3f0be3483a0/00602547288233.rgb.jpg/600x600bb.jpg")
)

#Preview("Empty State") {
    let mockService = PreviewMockMusicService()
    let player = ShufflePlayer(musicService: mockService)
    PlayerView(
        player: player,
        musicService: mockService,
        onManageTapped: {},
        onAddTapped: {},
        onSettingsTapped: {}
    )
}

#Preview("Playing") {
    ZStack {
        // Local asset for preview (network images don't load in previews)
        GeometryReader { geometry in
            Image("SampleAlbumArt")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
                .blur(radius: 3)
                .ignoresSafeArea()
        }

        VStack(spacing: 0) {
            // Top bar
            HStack {
                Button(action: {}) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(ShuffleTheme.silver.bodyGradientTop)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .strokeBorder(.white.opacity(0.3), lineWidth: 1)
                        )
                }
                Spacer()
                Button(action: {}) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(ShuffleTheme.silver.bodyGradientTop)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .strokeBorder(.white.opacity(0.3), lineWidth: 1)
                        )
                }
            }
            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
            .padding(.horizontal, 20)
            .padding(.top, 60)

            Spacer()

            // Song info panel - brushed metal
            ShuffleBodyView(highlightOffset: .zero, height: 120) {
                VStack(spacing: 4) {
                    Text(previewSong.title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(ShuffleTheme.silver.textColor)
                        .lineLimit(1)
                    Text(previewSong.artist)
                        .font(.system(size: 14))
                        .foregroundStyle(ShuffleTheme.silver.secondaryTextColor)
                        .lineLimit(1)

                    PlaybackProgressBar(currentTime: 78, duration: 242)
                        .padding(.top, 8)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .padding(.horizontal, 20)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            // Controls panel - brushed metal
            ShuffleBodyView(highlightOffset: .zero) {
                ClickWheelView(
                    isPlaying: true,
                    onPlayPause: {},
                    onSkipForward: {},
                    onSkipBack: {},
                    onVolumeUp: {},
                    onVolumeDown: {},
                    highlightOffset: .zero,
                    scale: 0.6
                )
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 34)
        }
    }
    .environment(\.shuffleTheme, .silver)
}
