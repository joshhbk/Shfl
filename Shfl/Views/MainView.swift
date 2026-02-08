import SwiftUI
import SwiftData

struct MainView: View {
    @State private var viewModel: AppViewModel
    @State private var appSettings: AppSettings

    init(musicService: MusicService, modelContext: ModelContext) {
        let settings = AppSettings()
        _appSettings = State(wrappedValue: settings)
        _viewModel = State(wrappedValue: AppViewModel(
            musicService: musicService,
            modelContext: modelContext,
            appSettings: settings
        ))
    }

    var body: some View {
        Group {
            if viewModel.isLoading {
                loadingView
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
            } else {
                authorizationView
            }
        }
        .environment(\.appSettings, appSettings)
        .onAppear {
            VolumeController.initialize()
        }
        .task {
            await viewModel.onAppear()
        }
        .onChange(of: appSettings.shuffleAlgorithm) { _, newAlgorithm in
            Task {
                await viewModel.onShuffleAlgorithmChanged(newAlgorithm)
            }
        }
        .sheet(isPresented: Binding(
            get: { viewModel.showingManage },
            set: { viewModel.showingManage = $0 }
        )) {
            ManageView(
                player: viewModel.player,
                onAddTapped: { viewModel.openPicker() },
                onRemoveSong: { songId in
                    Task { await viewModel.removeSong(id: songId) }
                },
                onDismiss: { viewModel.closeManage() }
            )
            .environment(\.appSettings, appSettings)
            .sheet(isPresented: Binding(
                get: { viewModel.showingPicker },
                set: { viewModel.showingPicker = $0 }
            ), onDismiss: { viewModel.closePicker() }) {
                SongPickerView(
                    player: viewModel.player,
                    musicService: viewModel.musicService,
                    initialSortOption: appSettings.librarySortOption,
                    onAddSong: { song in try await viewModel.addSong(song) },
                    onAddSongsWithQueueRebuild: { songs in try await viewModel.addSongsWithQueueRebuild(songs) },
                    onRemoveSong: { songId in await viewModel.removeSong(id: songId) },
                    onRemoveAllSongs: { await viewModel.removeAllSongs() },
                    onDismiss: { viewModel.closePicker() }
                )
                .environment(\.appSettings, appSettings)
            }
        }
        .sheet(isPresented: Binding(
            get: { viewModel.showingPickerDirect },
            set: { viewModel.showingPickerDirect = $0 }
        ), onDismiss: { viewModel.closePickerDirect() }) {
            SongPickerView(
                player: viewModel.player,
                musicService: viewModel.musicService,
                initialSortOption: appSettings.librarySortOption,
                onAddSong: { song in try await viewModel.addSong(song) },
                onAddSongsWithQueueRebuild: { songs in try await viewModel.addSongsWithQueueRebuild(songs) },
                onRemoveSong: { songId in await viewModel.removeSong(id: songId) },
                onRemoveAllSongs: { await viewModel.removeAllSongs() },
                onDismiss: { viewModel.closePickerDirect() }
            )
            .environment(\.appSettings, appSettings)
        }
        .sheet(isPresented: Binding(
            get: { viewModel.showingSettings },
            set: { viewModel.showingSettings = $0 }
        )) {
            SettingsView()
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

    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)

            Text(viewModel.loadingMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var authorizationView: some View {
        VStack(spacing: 24) {
            Image(systemName: "music.note.list")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("Welcome to Shuffled")
                    .font(.title2.bold())

                Text("Connect to Apple Music to start shuffling")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button("Connect Apple Music") {
                Task {
                    await viewModel.requestAuthorization()
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(32)
    }
}
