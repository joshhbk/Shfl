import ShflAppleMusicUI
import ShflComposition
import ShflCore
import ShflDeterministic
import SwiftUI
import Vortex

struct PlayerView: View {
    var player: ShufflePlayer
    let draft: SessionDraftStore
    /// Called once, when the player first appears.
    let makePlaybackClock: () -> PlaybackClock
    let onAddTapped: () -> Void
    let onSettingsTapped: () -> Void
    let onSkipForwardTapped: () -> Void
    let onSkipBackTapped: () -> Void

    @Environment(\.appearanceSettings) private var appearanceSettings
    @Environment(\.listeningSessionHost) private var sessionHost
    @Environment(\.artworkStore) private var artworkStore
    @State private var themeController: ThemeController
    @State private var tintProvider: TintedThemeProvider
    @State private var playbackClock: PlaybackClock?
    @State private var colorExtractor = AlbumArtColorExtractor()
    @State private var showError = false
    @State private var errorMessage = ""

    init(
        player: ShufflePlayer,
        draft: SessionDraftStore,
        makePlaybackClock: @escaping () -> PlaybackClock,
        initialThemeId: String? = nil,
        onAddTapped: @escaping () -> Void = {},
        onSettingsTapped: @escaping () -> Void = {},
        onSkipForwardTapped: @escaping () -> Void = {},
        onSkipBackTapped: @escaping () -> Void = {}
    ) {
        self.player = player
        self.draft = draft
        self.makePlaybackClock = makePlaybackClock
        self.onAddTapped = onAddTapped
        self.onSettingsTapped = onSettingsTapped
        self.onSkipForwardTapped = onSkipForwardTapped
        self.onSkipBackTapped = onSkipBackTapped
        self._themeController = State(wrappedValue: ThemeController(themeId: initialThemeId))
        let initialTheme = initialThemeId.flatMap { ShuffleTheme.theme(byId: $0) } ?? .pink
        self._tintProvider = State(wrappedValue: TintedThemeProvider(theme: initialTheme))
    }

    private var isStartingSession: Bool {
        sessionHost?.isStartingSession ?? player.isLoadingSession
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                BrushedMetalBackground()

                if player.playbackState.currentSong == nil && !isStartingSession {
                    IdleShuffleParticles(currentTheme: themeController.currentTheme)
                }

                ClassicPlayerLayout(
                    playbackState: player.playbackState,
                    hasSongs: !draft.isEmpty,
                    playbackClock: playbackClock,
                    onPlayPause: { Task { await sessionHost?.togglePlayback() } },
                    onSkipForward: onSkipForwardTapped,
                    onSkipBack: onSkipBackTapped,
                    onAdd: onAddTapped,
                    onSettings: onSettingsTapped,
                    onSeek: { time in
                        playbackClock?.handleUserSeek(to: time)
                        player.seek(to: time)
                    },
                    isShuffling: isStartingSession,
                    showError: showError,
                    errorMessage: errorMessage,
                    safeAreaInsets: geometry.safeAreaInsets,
                    onDismissError: {
                        withAnimation {
                            showError = false
                        }
                        player.clearOperationNotice()
                    }
                )
            }
            .ignoresSafeArea()
        }
        .simultaneousGesture(themeController.makeSwipeGesture())
        .environment(\.shuffleTheme, tintProvider.computedTheme)
        .onAppear {
            if playbackClock == nil {
                playbackClock = makePlaybackClock()
            }
            playbackClock?.startUpdating(playbackState: player.playbackState)

            // Initialize tint provider with current theme
            tintProvider.update(albumColor: colorExtractor.extractedColor, theme: themeController.currentTheme)

            if let song = player.playbackState.currentSong {
                colorExtractor.updateColor(for: song.id, lookUpColors: artworkColorLookup)
            }
        }
        .onDisappear {
            playbackClock?.stopUpdating()
        }
        .onChange(of: player.playbackState) { _, newState in
            handlePlaybackStateChange(newState)
        }
        .onChange(of: player.operationNotice) { _, notice in
            guard let notice else { return }
            errorMessage = notice
            withAnimation {
                showError = true
            }
        }
        .onChange(of: colorExtractor.extractedColor) { _, newColor in
            tintProvider.update(albumColor: newColor, theme: themeController.currentTheme)
        }
        // This two-way sync only terminates because both sides ignore no-op writes.
        .onChange(of: themeController.currentTheme) { _, newTheme in
            tintProvider.update(albumColor: colorExtractor.extractedColor, theme: newTheme)
            appearanceSettings?.currentThemeId = newTheme.id
        }
        .onChange(of: appearanceSettings?.currentThemeId) { _, newId in
            guard let id = newId else { return }
            themeController.setTheme(byId: id)
        }
    }

    private var artworkColorLookup: AlbumArtColorExtractor.ColorLookup? {
        artworkStore.map { ArtworkPalette(store: $0).colors(for:) }
    }

    // MARK: - State Handlers

    private func handlePlaybackStateChange(_ newState: PlaybackState) {
        if case .error(let error) = newState {
            errorMessage = error.localizedDescription
            withAnimation {
                showError = true
            }
        }

        playbackClock?.handlePlaybackStateChange(newState)

        if let song = newState.currentSong {
            colorExtractor.updateColor(for: song.id, lookUpColors: artworkColorLookup)
        } else {
            colorExtractor.clear()
        }
    }

}

// MARK: - Idle Particles (dialed-down Vortex — ~6 particles alive vs ~32 in ShuffleParticles)

private struct IdleShuffleParticles: View {
    let currentTheme: ShuffleTheme
    private let particleThemes: [ShuffleTheme]
    private let system: VortexSystem

    init(currentTheme: ShuffleTheme) {
        self.currentTheme = currentTheme
        let particleThemes = ShuffleTheme.allThemes.filter { $0.id != currentTheme.id }
        self.particleThemes = particleThemes
        self.system = Self.makeSystem(tags: particleThemes.map { "theme-\($0.id)" })
    }

    var body: some View {
        VortexView(system) {
            ForEach(particleThemes) { theme in
                Circle()
                    .fill(theme.bodyGradientTop.opacity(0.5))
                    .frame(width: 45)
                    .tag("theme-\(theme.id)")
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }

    private static func makeSystem(tags: [String]) -> VortexSystem {
        let system = VortexSystem(tags: tags)
        system.birthRate = 2
        system.lifespan = 3
        system.speed = 0.15
        system.speedVariation = 0.1
        system.angle = .zero
        system.angleRange = .degrees(360)
        system.size = 0.4
        system.sizeVariation = 0.3
        system.position = [0.5, 0.5]
        system.shape = .ellipse(radius: 0.3)
        return system
    }
}

// MARK: - Previews

private enum PreviewPlayerState: String, CaseIterable, Identifiable {
    case empty
    case armed
    case loading
    case playing
    case paused
    case error

    var id: String { rawValue }
}

private struct PreviewPlaybackError: LocalizedError, Sendable {
    let errorDescription: String?
}

private let previewSong = Song(
    id: "preview-1",
    title: "Bohemian Rhapsody",
    artist: "Queen",
    albumTitle: "A Night at the Opera",
    artworkURL: URL(string: "https://is1-ssl.mzstatic.com/image/thumb/Music115/v4/3c/1b/a9/3c1ba9e1-cf27-f6d1-6287-a3f0be3483a0/00602547288233.rgb.jpg/600x600bb.jpg")
)

private let previewQueueSongs = [
    previewSong,
    Song(
        id: "preview-2",
        title: "Dreams",
        artist: "Fleetwood Mac",
        albumTitle: "Rumours",
        artworkURL: nil
    )
]

private struct PlayerViewPreviewHost: View {
    @State private var model: AppModel
    private let themeId: String

    init(state: PreviewPlayerState, themeId: String) {
        self.themeId = themeId

        let initialPlaybackState: PlaybackState = switch state {
        case .empty, .armed: .empty
        case .loading: .loading(previewSong)
        case .playing: .playing(previewSong)
        case .paused: .paused(previewSong)
        case .error: .error(PreviewPlaybackError(errorDescription: "Preview playback failed."))
        }
        let draft: [Song] = switch state {
        case .empty: []
        case .armed, .loading, .playing, .paused, .error: previewQueueSongs
        }
        _model = State(
            wrappedValue: AppModel.preview(
                library: DeterministicLibrary(songs: previewQueueSongs),
                playback: DeterministicPlayback(state: initialPlaybackState, time: 78, duration: 242),
                draft: draft
            )
        )
    }

    var body: some View {
        PlayerView(
            player: model.player,
            draft: model.sessionDraft,
            makePlaybackClock: model.makePlaybackClock,
            initialThemeId: themeId,
            onAddTapped: {},
            onSettingsTapped: {},
            onSkipForwardTapped: {},
            onSkipBackTapped: {}
        )
    }
}

#Preview("Empty State") {
    PlayerViewPreviewHost(state: .empty, themeId: "silver")
}

#Preview("Armed State") {
    PlayerViewPreviewHost(state: .armed, themeId: "silver")
}

#Preview("Loading") {
    PlayerViewPreviewHost(state: .loading, themeId: "silver")
}

#Preview("Playing") {
    PlayerViewPreviewHost(state: .playing, themeId: "silver")
}

#Preview("Paused") {
    PlayerViewPreviewHost(state: .paused, themeId: "silver")
}

#Preview("Error") {
    PlayerViewPreviewHost(state: .error, themeId: "silver")
}
