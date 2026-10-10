import SwiftUI

struct MainView: View {
    @Bindable var model: AppModel
    let appSettings: AppSettings

    @State private var hasStartedInitialLoad = false
    @State private var hasCompletedInitialLoad = false
    @State private var hasCompletedSplashTimeline = false
    @State private var hasDismissedStartupSplash = false

    init(
        model: AppModel,
        appSettings: AppSettings,
        showsStartupSplash: Bool = true
    ) {
        self.model = model
        self.appSettings = appSettings
        _hasCompletedSplashTimeline = State(initialValue: !showsStartupSplash)
        _hasDismissedStartupSplash = State(initialValue: !showsStartupSplash)
    }

    private enum LaunchPhase: Int {
        case loading
        case unauthorized
        case ready
    }

    private var loadingTheme: ShuffleTheme {
        ShuffleTheme.theme(byId: appSettings.currentThemeId) ?? .pink
    }

    private var launchPhase: LaunchPhase {
        if model.isLoading {
            return .loading
        }
        return model.isAuthorized ? .ready : .unauthorized
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
        .onChange(of: model.isLoading) { _, _ in
            dismissSplashIfReady()
        }
        .onChange(of: appSettings.shuffleAlgorithm) { _, newAlgorithm in
            model.sessionDraft.stage(newAlgorithm)
        }
        .sheet(isPresented: $model.showingPicker, onDismiss: { model.closePicker() }) {
            songPickerSheet(onDismiss: { model.closePicker() })
        }
        .sheet(isPresented: $model.showingSettings) {
            SettingsView()
                .tint(deviceAccentColor)
                .environment(\.appSettings, appSettings)
                .environment(\.shufflePlayer, model.player)
                .environment(\.lastFMTransport, model.lastFMTransport)
        }
        .alert("Authorization Required", isPresented: .init(
            get: { model.authorizationError != nil },
            set: { if !$0 { model.authorizationError = nil } }
        )) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let error = model.authorizationError {
                Text(error)
            }
        }
        // Kept last so the sheets above can read them too.
        .environment(\.sessionDraft, model.sessionDraft)
        .environment(\.listeningSessionHost, model.sessionHost)
    }

    @ViewBuilder
    private func songPickerSheet(onDismiss: @escaping () -> Void) -> some View {
        SongPickerView(
            libraryCatalog: model.library,
            initialSortOption: appSettings.librarySortOption,
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
        if model.isLoading {
            LoadingView(message: "Loading...")
                .environment(\.shuffleTheme, loadingTheme)
                .transition(.opacity)
        } else if model.isAuthorized {
            PlayerView(
                player: model.player,
                playbackTransport: model.playbackTransport,
                initialThemeId: appSettings.currentThemeId,
                onAddTapped: { model.openPicker() },
                onSettingsTapped: { model.openSettings() },
                onSkipForwardTapped: { Task { try? await model.player.skipToNext() } },
                onSkipBackTapped: { Task { try? await model.player.restartOrSkipToPrevious() } }
            )
            .transition(.opacity)
        } else {
            WelcomeView {
                Task { await model.requestAuthorization() }
            }
            .transition(.opacity)
        }
    }

    @MainActor
    private func startInitialLoadIfNeeded() async {
        guard !hasStartedInitialLoad else { return }
        hasStartedInitialLoad = true

        await Task.yield()
        await model.onAppear()
        hasCompletedInitialLoad = true
        VolumeController.initialize()
        dismissSplashIfReady()
    }

    @MainActor
    private func dismissSplashIfReady() {
        guard !hasDismissedStartupSplash,
              hasCompletedSplashTimeline,
              hasCompletedInitialLoad,
              !model.isLoading else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            hasDismissedStartupSplash = true
        }
    }

}
