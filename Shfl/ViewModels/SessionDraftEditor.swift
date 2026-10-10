import Foundation

/// What toggling a song did to the session draft.
enum DraftEdit: Equatable {
    /// The song joined the pool, which now holds `songCount` songs.
    case added(songCount: Int, reachedMilestone: Bool)
    case removed
    /// The pool was full, so the song stayed out.
    case rejectedAtCapacity
    /// The edit failed; the message is also shown as `actionErrorMessage`.
    case failed(String)
}

/// The song picker's editing state: the error banner, and whether
/// autofill has run out of songs. Edits go straight to the
/// `SessionDraftStore` passed in.
@Observable
@MainActor
final class SessionDraftEditor {
    deinit {} // Keep nonisolated: Xcode 27 synthesizes an isolated one that can crash on release. See ViewTeardownTests.
    private(set) var actionErrorMessage: String?
    private(set) var autofillIsExhausted = false

    // MARK: - Editing

    /// Adds the song to the draft, or removes it when it is already there.
    @discardableResult
    func toggle(_ song: Song, in draft: SessionDraftStore) -> DraftEdit {
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
            showActionError(error.localizedDescription)
            return .failed(error.localizedDescription)
        }
    }

    func clearAll(in draft: SessionDraftStore) {
        autofillIsExhausted = false
        draft.removeAll()
    }

    /// Autofill is exhausted when it came back short while there was still
    /// room, so the library has no more songs to offer.
    func noteAutofillCompleted(addedCount: Int, requestedCount: Int, remainingCapacity: Int) {
        autofillIsExhausted = addedCount < requestedCount && remainingCapacity > 0
    }

    /// Shows `message` for three seconds.
    func showActionError(_ message: String) {
        actionErrorMessage = message

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            if actionErrorMessage == message {
                actionErrorMessage = nil
            }
        }
    }
}
