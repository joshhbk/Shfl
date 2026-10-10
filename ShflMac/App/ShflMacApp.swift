import ShflComposition
import SwiftUI

@main
struct ShflMacApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: ShflMacAppDelegate

    var body: some Scene {
        Window("Shuffled", id: "main") {
            LaunchRootView(model: appDelegate.model)
                .shellEnvironment(appDelegate.shell)
        }
        .defaultSize(width: 1100, height: 700)
        .commands {
            PlaybackCommands(
                sessionHost: appDelegate.model.sessionHost,
                player: appDelegate.model.player
            )
            SongsCommands(drafting: appDelegate.shell.drafting)
        }

        Settings {
            ShflSettingsView()
                .shellEnvironment(appDelegate.shell)
        }
    }
}
