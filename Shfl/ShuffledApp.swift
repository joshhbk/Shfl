//
//  ShuffledApp.swift
//  Shuffled
//
//  Created by Joshua Hughes on 2025-12-25.
//

import SwiftUI
import SwiftData

@main
struct ShuffledApp: App {
    @State private var appSettings: AppSettings
    @State private var appViewModel: AppViewModel

    private let sharedModelContainer: ModelContainer

    private var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    init() {
        let schema = Schema([
            PersistedSong.self,
            PersistedPlaybackState.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            self.sharedModelContainer = container

            let settings = AppSettings()
            let musicService = AppleMusicService()
            _appSettings = State(wrappedValue: settings)
            _appViewModel = State(
                wrappedValue: AppViewModel(
                    musicService: musicService,
                    modelContext: container.mainContext,
                    appSettings: settings
                )
            )
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            if isRunningTests {
                Color.clear
            } else {
                MainView(viewModel: appViewModel, appSettings: appSettings)
            }
        }
        .modelContainer(sharedModelContainer)
    }
}
