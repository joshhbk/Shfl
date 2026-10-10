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
/// out of songs.
@Observable
@MainActor
public final class SessionDraftEditor {
    deinit {} // Keep nonisolated: Xcode 27 synthesizes an isolated one that can crash on release. See ViewTeardownTests.
    public private(set) var autofillIsExhausted = false

    @ObservationIgnored private let draft: SessionDraftStore

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

    public func noteAutofillCompleted(addedCount: Int, requestedCount: Int, remainingCapacity: Int) {
        autofillIsExhausted = addedCount < requestedCount && remainingCapacity > 0
    }
}
