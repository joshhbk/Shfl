//
//  ShuffledApp.swift
//  Shuffled
//
//  Created by Joshua Hughes on 2025-12-25.
//

import ShflAppleMusicUI
import ShflCore
import SwiftUI
import SwiftData

@main
struct ShuffledApp: App {
    @State private var libraryPreferences: LibraryPreferences
    @State private var appearanceSettings: AppearanceSettings
    @State private var appModel: AppModel

    private let composition: AppComposition

    init() {
        do {
            let composition = try AppComposition.make()
            self.composition = composition
            _libraryPreferences = State(wrappedValue: composition.libraryPreferences)
            _appearanceSettings = State(wrappedValue: composition.appearanceSettings)
            _appModel = State(wrappedValue: composition.appModel)
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            MainView(
                model: appModel,
                libraryPreferences: libraryPreferences,
                appearanceSettings: appearanceSettings,
                showsStartupSplash: composition.showsStartupSplash
            )
            .environment(\.artworkStore, composition.artworkStore)
        }
        .modelContainer(composition.modelContainer)
    }
}
