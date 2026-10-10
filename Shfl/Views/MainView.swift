import ShflCore
import SwiftUI

struct MainView: View {
    let model: AppModel
    let libraryPreferences: LibraryPreferences
    let appearanceSettings: AppearanceSettings

    @Environment(\.scenePhase) private var scenePhase

    @State private var showingPicker = false
    @State private var showingSettings = false
    @State private var showingAuthorizationAlert = false
    @State private var hasStartedInitialLoad = false
    @State private var hasCompletedInitialLoad = false
    @State private var hasCompletedSplashTimeline = false
    @State private var hasDismissedStartupSplash = false

    init(
        model: AppModel,
        libraryPreferences: LibraryPreferences,
        appearanceSettings: AppearanceSettings,
        showsStartupSplash: Bool = true
    ) {
        self.model = model
        self.libraryPreferences = libraryPreferences
        self.appearanceSettings = appearanceSettings
        _hasCompletedSplashTimeline = State(initialValue: !showsStartupSplash)
        _hasDismissedStartupSplash = State(initialValue: !showsStartupSplash)
    }

    private var loadingTheme: ShuffleTheme {
        ShuffleTheme.theme(byId: appearanceSettings.currentThemeId) ?? .pink
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
                    .animation(.easeInOut(duration: 0.35), value: model.launchPhase)
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
        .environment(\.libraryPreferences, libraryPreferences)
        .environment(\.appearanceSettings, appearanceSettings)
        .task {
            await startInitialLoadIfNeeded()
        }
        .onChange(of: model.launchPhase) { _, _ in
            dismissSplashIfReady()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                model.sceneDidLeaveForeground()
            }
        }
        .sheet(isPresented: $showingPicker) {
            songPickerSheet(onDismiss: { showingPicker = false })
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .tint(deviceAccentColor)
                .environment(\.libraryPreferences, libraryPreferences)
                .environment(\.appearanceSettings, appearanceSettings)
                .environment(\.shufflePlayer, model.player)
                .environment(\.lastFMTransport, model.lastFMTransport)
        }
        .alert("Authorization Required", isPresented: $showingAuthorizationAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Apple Music access is required to use Shuffled. Please enable it in Settings.")
        }
        // Kept last so the sheets above can read them too.
        .environment(\.sessionDraft, model.sessionDraft)
        .environment(\.listeningSessionHost, model.sessionHost)
    }

    @ViewBuilder
    private func songPickerSheet(onDismiss: @escaping () -> Void) -> some View {
        SongPickerView(
            libraryCatalog: model.library,
            libraryPreferences: libraryPreferences,
            onDismiss: onDismiss
        )
        .tint(deviceAccentColor)
        .environment(\.shuffleTheme, currentTheme)
        .environment(\.libraryPreferences, libraryPreferences)
        .environment(\.appearanceSettings, appearanceSettings)
    }

    private var currentTheme: ShuffleTheme {
        ShuffleTheme.theme(byId: appearanceSettings.currentThemeId) ?? .pink
    }

    private var deviceAccentColor: Color {
        (ShuffleTheme.theme(byId: appearanceSettings.currentThemeId) ?? .pink).accentColor
    }

    @ViewBuilder
    private var launchContent: some View {
        switch model.launchPhase {
        case .loading:
            LoadingView(message: "Loading...")
                .environment(\.shuffleTheme, loadingTheme)
                .transition(.opacity)
        case .ready:
            PlayerView(
                player: model.player,
                playbackTransport: model.playbackTransport,
                initialThemeId: appearanceSettings.currentThemeId,
                onAddTapped: { showingPicker = true },
                onSettingsTapped: { showingSettings = true },
                onSkipForwardTapped: { Task { try? await model.player.skipToNext() } },
                onSkipBackTapped: { Task { try? await model.player.restartOrSkipToPrevious() } }
            )
            .transition(.opacity)
        case .needsAuthorization, .authorizationDenied:
            WelcomeView {
                Task { await requestAuthorization() }
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

    private func requestAuthorization() async {
        await model.requestAuthorization()
        if model.launchPhase == .authorizationDenied {
            showingAuthorizationAlert = true
        }
    }

    @MainActor
    private func dismissSplashIfReady() {
        guard !hasDismissedStartupSplash,
              hasCompletedSplashTimeline,
              hasCompletedInitialLoad,
              model.launchPhase != .loading else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            hasDismissedStartupSplash = true
        }
    }

}
