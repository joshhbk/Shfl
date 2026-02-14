import SwiftUI

struct MainView: View {
    @Bindable var viewModel: AppViewModel
    let appSettings: AppSettings

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
        .tint(deviceAccentColor)
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
        .environment(\.appSettings, appSettings)
    }

    private var deviceAccentColor: Color {
        (ShuffleTheme.theme(byId: appSettings.currentThemeId) ?? .pink).accentColor
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
