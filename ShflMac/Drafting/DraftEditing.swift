import Observation
import ShflCore

@Observable
@MainActor
final class DraftEditing {
    deinit {} // Keep nonisolated: Xcode 27 synthesizes an isolated one that can crash on release. See ViewTeardownTests.

    private(set) var milestonePulses = 0
    private(set) var failureMessage: String?

    @ObservationIgnored private let editor: SessionDraftEditor
    @ObservationIgnored private let browser: LibraryBrowser
    @ObservationIgnored private let beep: () -> Void

    init(editor: SessionDraftEditor, browser: LibraryBrowser, beep: @escaping () -> Void) {
        self.editor = editor
        self.browser = browser
        self.beep = beep
    }

    var draft: SessionDraftStore { editor.draft }

    var songIDs: Set<String> { Set(draft.songs.map(\.id)) }

    func toggle(_ song: Song) {
        give(feedbackFor: editor.toggle(song))
    }

    func add(_ songs: [Song]) {
        give(feedbackFor: editor.add(songs))
    }

    func remove(_ songs: [Song]) {
        let inDraft = songIDs
        for song in songs where inDraft.contains(song.id) {
            give(feedbackFor: editor.toggle(song))
        }
    }

    var canAutofill: Bool { editor.canAutofill(using: browser) }

    func clearAll() {
        failureMessage = nil
        editor.clearAll()
    }

    func autofill() async {
        failureMessage = nil
        await editor.autofill(using: browser)
        if case .error(let message) = browser.autofillState {
            failureMessage = message
        }
    }

    func dismissFailure() {
        failureMessage = nil
    }

    private func give(feedbackFor edit: DraftEdit) {
        switch edit {
        case .added(_, let reachedMilestone):
            failureMessage = nil
            if reachedMilestone { milestonePulses += 1 }
        case .removed:
            failureMessage = nil
        case .rejectedAtCapacity:
            beep()
        case .failed(let message):
            failureMessage = message
        }
    }
}
