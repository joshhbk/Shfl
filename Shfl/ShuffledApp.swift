//
//  ShuffledApp.swift
//  Shuffled
//
//  Created by Joshua Hughes on 2025-12-25.
//

import ShflAppleMusicUI
import ShflComposition
import SwiftUI

@main
struct ShuffledApp: App {
    @State private var appModel: AppModel
    @State private var appearanceSettings: AppearanceSettings
    private let showsStartupSplash: Bool

    init() {
        let composition: AppComposition
        do {
            composition = try AppComposition.make()
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
        _appModel = State(wrappedValue: composition.appModel)

        let appearanceSettings = AppearanceSettings(defaults: composition.userDefaults)
        switch composition.mode {
        case .live:
            showsStartupSplash = true
        case .deterministic:
            // Scenarios start straight away on a fixed theme.
            appearanceSettings.currentThemeId = "silver"
            showsStartupSplash = false
        }
        _appearanceSettings = State(wrappedValue: appearanceSettings)
    }

    var body: some Scene {
        WindowGroup {
            MainView(
                model: appModel,
                appearanceSettings: appearanceSettings,
                showsStartupSplash: showsStartupSplash
            )
            .environment(\.artworkStore, appModel.artworkStore)
        }
    }
}
