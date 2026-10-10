import AppKit
import ShflComposition

/// Owns the launch's models, so they live exactly as long as the app.
final class ShflMacAppDelegate: NSObject, NSApplicationDelegate {
    deinit {} // Keep nonisolated: Xcode 27 synthesizes an isolated one that can crash on release. See ViewTeardownTests.

    let model: AppModel
    let shell: Shell

    override init() {
        let composition: AppComposition
        do {
            composition = try AppComposition.make()
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
        model = composition.appModel
        shell = Shell(model: model)
        super.init()
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Unit tests are hosted by the app. Keep that app from taking focus
        // from whoever is using the Mac while they run.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            NSApp.setActivationPolicy(.prohibited)
        }
    }
}
