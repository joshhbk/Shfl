import AppKit
import ShflComposition

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
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            NSApp.setActivationPolicy(.prohibited)
        }
    }

    func applicationDidResignActive(_ notification: Notification) {
        model.sceneDidLeaveForeground()
    }

    func applicationDidHide(_ notification: Notification) {
        model.sceneDidLeaveForeground()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.sceneDidLeaveForeground()
    }
}
