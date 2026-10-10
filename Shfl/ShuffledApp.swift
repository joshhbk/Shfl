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
    @State private var appModel: AppModel

    private let composition: AppComposition

    init() {
        do {
            let composition = try AppComposition.make()
            self.composition = composition
            _appSettings = State(wrappedValue: composition.appSettings)
            _appModel = State(wrappedValue: composition.appModel)
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            MainView(
                model: appModel,
                appSettings: appSettings,
                showsStartupSplash: composition.showsStartupSplash
            )
        }
        .modelContainer(composition.modelContainer)
    }
}
