import Foundation

public enum DraftEdit: Equatable {
    case added(songCount: Int, milestone: Int?)
    case removed
    case rejectedAtCapacity
    case failed(String)
}

/// The picker reads the draft through here, so it always shows the draft it edits.
@Observable
@MainActor
public final class SessionDraftEditor {
    deinit {} // Keep nonisolated: Xcode 27 synthesizes an isolated one that can crash on release. See ViewTeardownTests.
    public private(set) var autofillIsExhausted = false

    @ObservationIgnored public let draft: SessionDraftStore

    package init(draft: SessionDraftStore) {
        self.draft = draft
    }

    // MARK: - Editing

    @discardableResult
    public func toggle(_ song: Song) -> DraftEdit {
        guard draft.contains(song.id) else { return add([song]) }
        autofillIsExhausted = false
        draft.remove(songID: song.id)
        return .removed
    }

    /// All or none: if the songs don't all fit, the draft is unchanged.
    @discardableResult
    public func add(_ songs: [Song]) -> DraftEdit {
        let before = draft.songCount
        guard songs.contains(where: { !draft.contains($0.id) }) else {
            return .added(songCount: before, milestone: nil)
        }
        autofillIsExhausted = false
        do {
            try draft.add(songs)
        } catch ShufflePlayerError.capacityReached {
            return .rejectedAtCapacity
        } catch {
            return .failed(error.localizedDescription)
        }
        return .added(songCount: draft.songCount, milestone: draft.milestone(reachedFrom: before))
    }

    public func canAutofill(using browser: LibraryBrowser) -> Bool {
        !draft.isAtCapacity && !autofillIsExhausted && browser.autofillState != .loading
    }

    public func clearAll() {
        autofillIsExhausted = false
        draft.removeAll()
    }

    public func autofill(using browser: LibraryBrowser) async {
        let requestedCount = draft.remainingCapacity
        await browser.autofill(into: draft)
        if case .completed(let count) = browser.autofillState {
            noteAutofillCompleted(
                addedCount: count,
                requestedCount: requestedCount,
                remainingCapacity: draft.remainingCapacity
            )
        }
    }

    func noteAutofillCompleted(addedCount: Int, requestedCount: Int, remainingCapacity: Int) {
        autofillIsExhausted = addedCount < requestedCount && remainingCapacity > 0
    }
}
