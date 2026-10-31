import ShflComposition
import SwiftUI

@main
struct ShflMacApp: App {
    static let mainWindowID = "main"

    @NSApplicationDelegateAdaptor private var appDelegate: ShflMacAppDelegate

    var body: some Scene {
        Window("Shuffled", id: Self.mainWindowID) {
            LaunchRootView(model: appDelegate.model)
                .shellEnvironment(appDelegate.shell)
        }
        .defaultSize(width: 1280, height: 760)
        .commands {
            PlaybackCommands(sessionHost: appDelegate.model.sessionHost)
            PicksCommands(drafting: appDelegate.shell.drafting, preferences: appDelegate.model.libraryPreferences)
            SortCommands(browser: appDelegate.shell.browser)
            #if DEBUG
            DesignCatalogCommands()
            #endif
        }

        MenuBarExtra(isInserted: .constant(!appDelegate.isRunningTests)) {
            MenuBarPlayer()
                .shellEnvironment(appDelegate.shell)
        } label: {
            MenuBarLabel(sessionHost: appDelegate.model.sessionHost)
        }
        .menuBarExtraStyle(.window)

        #if DEBUG
        Window("Design Catalog", id: DesignCatalogView.windowID) {
            DesignCatalogView()
        }
        .defaultSize(width: 980, height: 820)
        #endif

        Settings {
            ShflSettingsView()
                .shellEnvironment(appDelegate.shell)
        }
    }
}
