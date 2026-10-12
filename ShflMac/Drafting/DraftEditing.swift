import Observation
import ShflCore

@Observable
@MainActor
final class DraftEditing {
    deinit {} // Keep nonisolated: Xcode 27 synthesizes an isolated one that can crash on release. See ViewTeardownTests.

    private(set) var moment: PicksMoment?
    private(set) var failureMessage: String?

    @ObservationIgnored private let editor: SessionDraftEditor
    @ObservationIgnored private let browser: LibraryBrowser
    @ObservationIgnored private let beep: () -> Void
    @ObservationIgnored private var momentCount = 0

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
        let before = draft.songCount
        await editor.autofill(using: browser)
        if case .error(let message) = browser.autofillState {
            failureMessage = message
        }
        if let milestone = draft.milestone(reachedFrom: before) {
            mark(.milestone(milestone))
        }
    }

    func dismissFailure() {
        failureMessage = nil
    }

    private func give(feedbackFor edit: DraftEdit) {
        switch edit {
        case .added(_, let milestone):
            failureMessage = nil
            if let milestone { mark(.milestone(milestone)) }
        case .removed:
            failureMessage = nil
        case .rejectedAtCapacity:
            beep()
            mark(.noRoom)
        case .failed(let message):
            failureMessage = message
        }
    }

    private func mark(_ kind: PicksMoment.Kind) {
        momentCount += 1
        moment = PicksMoment(kind: kind, id: momentCount)
    }
}
