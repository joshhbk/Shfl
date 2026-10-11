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
        .defaultSize(width: 1100, height: 700)
        .commands {
            PlaybackCommands(sessionHost: appDelegate.model.sessionHost)
            SongsCommands(drafting: appDelegate.shell.drafting)
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
