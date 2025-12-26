import SwiftUI
import SwiftData

struct MainView: View {
    @StateObject private var viewModel: AppViewModel

    init(musicService: MusicService, modelContext: ModelContext) {
        _viewModel = StateObject(wrappedValue: AppViewModel(
            musicService: musicService,
            modelContext: modelContext
        ))
    }

    var body: some View {
        Group {
            if viewModel.isAuthorized {
                PlayerView(player: viewModel.player) {
                    viewModel.openManage()
                } onAddTapped: {
                    viewModel.openPickerDirect()
                }
            } else {
                authorizationView
            }
        }
        .task {
            await viewModel.onAppear()
        }
        .sheet(isPresented: $viewModel.showingManage) {
            ManageView(
                player: viewModel.player,
                onAddTapped: { viewModel.openPicker() },
                onDismiss: { viewModel.closeManage() }
            )
            .sheet(isPresented: $viewModel.showingPicker) {
                SongPickerView(
                    player: viewModel.player,
                    musicService: viewModel.musicService,
                    onDismiss: { viewModel.closePicker() }
                )
            }
        }
        .sheet(isPresented: $viewModel.showingPickerDirect) {
            SongPickerView(
                player: viewModel.player,
                musicService: viewModel.musicService,
                onDismiss: { viewModel.closePickerDirect() }
            )
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
