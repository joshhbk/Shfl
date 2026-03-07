import SwiftUI

struct MainView: View {
    @Bindable var viewModel: AppViewModel
    let appSettings: AppSettings

    @State private var hasStartedInitialLoad = false
    @State private var hasCompletedInitialLoad = false
    @State private var hasCompletedSplashTimeline = false
    @State private var hasDismissedStartupSplash = false

    private enum LaunchPhase: Int {
        case loading
        case unauthorized
        case ready
    }

    private var loadingTheme: ShuffleTheme {
        ShuffleTheme.theme(byId: appSettings.currentThemeId) ?? .pink
    }

    private var launchPhase: LaunchPhase {
        if viewModel.isLoading {
            return .loading
        }
        return viewModel.isAuthorized ? .ready : .unauthorized
    }

    private var shouldShowStartupSplash: Bool {
        !hasDismissedStartupSplash
    }

    private var shouldRenderLaunchContent: Bool {
        hasCompletedInitialLoad || !shouldShowStartupSplash
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(loadingTheme.bodyGradientTop)
                .ignoresSafeArea()

            if shouldRenderLaunchContent {
                launchContent
                    .animation(.easeInOut(duration: 0.35), value: launchPhase)
                    .zIndex(0)
            }

            if shouldShowStartupSplash {
                SplashView(theme: loadingTheme) {
                    hasCompletedSplashTimeline = true
                    dismissSplashIfReady()
                }
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .tint(deviceAccentColor)
        .environment(\.appSettings, appSettings)
        .task {
            await startInitialLoadIfNeeded()
        }
        .onChange(of: viewModel.isLoading) { _, _ in
            dismissSplashIfReady()
        }
        .onChange(of: viewModel.isAuthorized) { _, isAuthorized in
            guard isAuthorized,
                  !appSettings.hasCompletedOnboarding,
                  viewModel.player.queueState.songPool.isEmpty else { return }
            appSettings.hasCompletedOnboarding = true
            viewModel.isLoading = true
            viewModel.loadingMessage = "Finding songs in your library..."
            Task {
                await viewModel.autofillLibrary()
            }
        }
        .onChange(of: appSettings.shuffleAlgorithm) { _, newAlgorithm in
            Task {
                await viewModel.onShuffleAlgorithmChanged(newAlgorithm)
            }
        }
        .sheet(isPresented: $viewModel.showingManage) {
            ManageView(
                player: viewModel.player,
                onAddTapped: { viewModel.openPicker() },
                onRemoveSong: { songId in
                    Task { await viewModel.removeSong(id: songId) }
                },
                onDismiss: { viewModel.closeManage() }
            )
            .tint(deviceAccentColor)
            .environment(\.appSettings, appSettings)
            .sheet(isPresented: $viewModel.showingPicker, onDismiss: { viewModel.closePicker() }) {
                songPickerSheet(onDismiss: { viewModel.closePicker() })
            }
        }
        .sheet(isPresented: $viewModel.showingPickerDirect, onDismiss: { viewModel.closePickerDirect() }) {
            songPickerSheet(onDismiss: { viewModel.closePickerDirect() })
        }
        .sheet(isPresented: $viewModel.showingSettings) {
            SettingsView()
                .tint(deviceAccentColor)
                .environment(\.appSettings, appSettings)
                .environment(\.shufflePlayer, viewModel.player)
                .environment(\.lastFMTransport, viewModel.lastFMTransport)
        }
        .alert("Authorization Required", isPresented: .init(
            get: { viewModel.authorizationError != nil },
            set: { if !$0 { viewModel.authorizationError = nil } }
        )) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let error = viewModel.authorizationError {
                Text(error)
            }
        }
    }

    @ViewBuilder
    private func songPickerSheet(onDismiss: @escaping () -> Void) -> some View {
        SongPickerView(
            player: viewModel.player,
            musicService: viewModel.musicService,
            initialSortOption: appSettings.librarySortOption,
            onAddSong: { song in try await viewModel.addSong(song) },
            onAddSongsWithQueueRebuild: { songs in try await viewModel.addSongsWithQueueRebuild(songs) },
            onRemoveSong: { songId in await viewModel.removeSong(id: songId) },
            onRemoveAllSongs: { await viewModel.removeAllSongs() },
            onDismiss: onDismiss
        )
        .tint(deviceAccentColor)
        .environment(\.shuffleTheme, currentTheme)
        .environment(\.appSettings, appSettings)
    }

    private var currentTheme: ShuffleTheme {
        ShuffleTheme.theme(byId: appSettings.currentThemeId) ?? .pink
    }

    private var deviceAccentColor: Color {
        (ShuffleTheme.theme(byId: appSettings.currentThemeId) ?? .pink).accentColor
    }

    @ViewBuilder
    private var launchContent: some View {
        if viewModel.isLoading {
            LoadingView(message: viewModel.loadingMessage)
                .environment(\.shuffleTheme, loadingTheme)
                .transition(.opacity)
        } else if viewModel.isAuthorized {
            PlayerView(
                player: viewModel.player,
                musicService: viewModel.musicService,
                initialThemeId: appSettings.currentThemeId,
                onManageTapped: { viewModel.openManage() },
                onAddTapped: { viewModel.openPickerDirect() },
                onSettingsTapped: { viewModel.openSettings() },
                onPlayPauseTapped: { Task { await viewModel.togglePlayback() } },
                onSkipForwardTapped: { Task { await viewModel.skipToNext() } },
                onSkipBackTapped: { Task { await viewModel.restartOrSkipToPrevious() } },
                onShuffle: { Task { await viewModel.shuffleAll() } },
                isShuffling: viewModel.isShuffling
            )
            .transition(.opacity)
        } else {
            WelcomeView {
                Task { await viewModel.requestAuthorization() }
            }
            .transition(.opacity)
        }
    }

    @MainActor
    private func startInitialLoadIfNeeded() async {
        guard !hasStartedInitialLoad else { return }
        hasStartedInitialLoad = true

        await Task.yield()
        await viewModel.onAppear()
        hasCompletedInitialLoad = true
        VolumeController.initialize()
        dismissSplashIfReady()
    }

    @MainActor
    private func dismissSplashIfReady() {
        guard !hasDismissedStartupSplash,
              hasCompletedSplashTimeline,
              hasCompletedInitialLoad,
              !viewModel.isLoading else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            hasDismissedStartupSplash = true
        }
    }

}
