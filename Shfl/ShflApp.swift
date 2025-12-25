//
//  ShflApp.swift
//  Shfl
//
//  Created by Joshua Hughes on 2025-12-25.
//

import SwiftUI
import SwiftData

@main
struct ShflApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([PersistedSong.self])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            MainView(
                // TODO: Switch to AppleMusicService() once MusicKit entitlement is available
                musicService: MockMusicService(),
                modelContext: sharedModelContainer.mainContext
            )
        }
        .modelContainer(sharedModelContainer)
    }
}
