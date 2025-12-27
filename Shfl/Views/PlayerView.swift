import SwiftUI

struct PlayerView: View {
    @ObservedObject var player: ShufflePlayer
    let musicService: MusicService
    let onManageTapped: () -> Void
    let onAddTapped: () -> Void

    @State private var showError = false
    @State private var errorMessage = ""
    @State private var currentTime: TimeInterval = 0
    @State private var duration: TimeInterval = 0
    @State private var progressTimer: Timer?
    @State private var removedSong: Song?
    @State private var showUndoPill = false
    @State private var currentThemeIndex: Int = Int.random(in: 0..<ShuffleTheme.allThemes.count)
    @State private var dragOffset: CGFloat = 0

    private var currentTheme: ShuffleTheme {
        ShuffleTheme.allThemes[currentThemeIndex]
    }

    private let swipeThreshold: CGFloat = 100

    init(
        player: ShufflePlayer,
        musicService: MusicService,
        onManageTapped: @escaping () -> Void,
        onAddTapped: @escaping () -> Void = {}
    ) {
        self.player = player
        self.musicService = musicService
        self.onManageTapped = onManageTapped
        self.onAddTapped = onAddTapped
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                themedBackground(geometry: geometry)
                    .ignoresSafeArea()

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

                    topBar(geometry: geometry)

                    Spacer()

                    VStack(spacing: 32) {
                        nowPlayingSection

                        ClickWheelView(
                            isPlaying: player.playbackState.isPlaying,
                            onPlayPause: handlePlayPause,
                            onSkipForward: handleSkipForward,
                            onSkipBack: handleSkipBack,
                            onAdd: onAddTapped,
                            onRemove: handleRemove
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

                // Undo pill
                if showUndoPill, let song = removedSong {
                    VStack {
                        Spacer()
                        UndoPill(
                            state: UndoState(action: .removed, song: song),
                            onUndo: handleUndo,
                            onDismiss: {
                                withAnimation {
                                    showUndoPill = false
                                }
                            }
                        )
                        .padding(.bottom, geometry.safeAreaInsets.bottom + 60)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .gesture(themeSwipeGesture)
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.2), value: showError)
            .animation(.easeInOut(duration: 0.2), value: showUndoPill)
            .environment(\.shuffleTheme, currentTheme)
            .onChange(of: player.playbackState) { _, newState in
                handlePlaybackStateChange(newState)
            }
            .onAppear {
                startProgressTimer()
            }
            .onDisappear {
                stopProgressTimer()
            }
        }
    }

    @ViewBuilder
    private func topBar(geometry: GeometryProxy) -> some View {
        HStack {
            Spacer()
            CapacityIndicator(current: player.songCount, maximum: player.capacity)
            Spacer()
        }
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
    private func themedBackground(geometry: GeometryProxy) -> some View {
        let screenWidth = geometry.size.width
        let screenHeight = geometry.size.height + geometry.safeAreaInsets.top + geometry.safeAreaInsets.bottom

        HStack(spacing: 0) {
            ForEach(ShuffleTheme.allThemes) { theme in
                theme.bodyGradient
                    .frame(width: screenWidth, height: screenHeight)
            }
        }
        .offset(x: -CGFloat(currentThemeIndex) * screenWidth + dragOffset)
        .frame(width: screenWidth, height: screenHeight, alignment: .leading)
        .clipped()
    }

    private var themeSwipeGesture: some Gesture {
        DragGesture()
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
            try? await player.restartCurrentSong()
        }
    }

    private func handleRemove() {
        guard let currentSong = player.playbackState.currentSong else { return }

        removedSong = currentSong
        player.removeSong(id: currentSong.id)

        withAnimation {
            showUndoPill = true
        }

        // Auto-hide after 5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            withAnimation {
                showUndoPill = false
            }
        }
    }

    private func handleUndo() {
        guard let song = removedSong else { return }
        try? player.addSong(song)
        removedSong = nil
        withAnimation {
            showUndoPill = false
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
    func restartCurrentSong() async throws {}
}

#Preview("Empty State") {
    let mockService = PreviewMockMusicService()
    let player = ShufflePlayer(musicService: mockService)
    return PlayerView(
        player: player,
        musicService: mockService,
        onManageTapped: {},
        onAddTapped: {}
    )
}

#Preview("Playing") {
    let mockService = PreviewMockMusicService()
    let player = ShufflePlayer(musicService: mockService)
    return PlayerView(
        player: player,
        musicService: mockService,
        onManageTapped: {},
        onAddTapped: {}
    )
}
