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

    private let composition: AppComposition

    init() {
        do {
            let composition = try AppComposition.make()
            self.composition = composition
            _appSettings = State(wrappedValue: composition.appSettings)
            _appViewModel = State(wrappedValue: composition.appViewModel)
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            MainView(
                viewModel: appViewModel,
                appSettings: appSettings,
                showsStartupSplash: composition.showsStartupSplash
            )
        }
        .modelContainer(composition.modelContainer)
    }
}
