import ShflAppleMusicUI
import ShflComposition
import ShflCore
import SwiftUI

@MainActor
struct Shell {
    let model: AppModel
    let browser: LibraryBrowser
    let drafting: DraftEditing

    init(model: AppModel, beep: @escaping () -> Void = { NSSound.beep() }) {
        self.model = model
        browser = model.makeLibraryBrowser()
        drafting = DraftEditing(editor: model.makeDraftEditor(), browser: browser, beep: beep)
    }
}

extension View {
    func shellEnvironment(_ shell: Shell) -> some View {
        environment(shell.model.player)
            .environment(shell.model.sessionHost)
            .environment(shell.model.libraryPreferences)
            .environment(shell.model.lastFM)
            .environment(shell.browser)
            .environment(shell.drafting)
            .environment(\.artworkStore, shell.model.artworkStore)
            .environment(\.screenFactories, ScreenFactories(model: shell.model))
    }
}
