import Foundation

public enum DraftEdit: Equatable {
    case added(songCount: Int, reachedMilestone: Bool)
    case removed
    case rejectedAtCapacity
    /// The pool is unchanged. The message says why, for the listener; this is
    /// the only place it is reported.
    case failed(String)
}

/// The song picker's edits to one session draft, and whether autofill has run
/// out of songs. The picker reads the draft here too, so it always shows the
/// draft it edits.
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
        autofillIsExhausted = false

        if draft.contains(song.id) {
            draft.remove(songID: song.id)
            return .removed
        }

        do {
            try draft.add(song)
            return .added(
                songCount: draft.songCount,
                reachedMilestone: SessionDraft.milestones.contains(draft.songCount)
            )
        } catch ShufflePlayerError.capacityReached {
            return .rejectedAtCapacity
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    public func clearAll() {
        autofillIsExhausted = false
        draft.removeAll()
    }

    /// Fills the draft from `browser`'s library, which reports progress and
    /// the outcome in its `autofillState`.
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

    /// Autofill is exhausted when it came back short while there was still
    /// room, so the library has no more songs to offer.
    func noteAutofillCompleted(addedCount: Int, requestedCount: Int, remainingCapacity: Int) {
        autofillIsExhausted = addedCount < requestedCount && remainingCapacity > 0
    }
}
