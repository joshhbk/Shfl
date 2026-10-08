import SwiftUI

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

    func toggle(_ song: Song, in draft: SessionDraftStore) {
        autofillIsExhausted = false

        if draft.contains(song.id) {
            draft.remove(songID: song.id)
            return
        }

        do {
            try draft.add(song)
            if CapacityProgressBar.isMilestone(draft.songCount) {
                HapticFeedback.milestone.trigger()
            }
        } catch ShufflePlayerError.capacityReached {
            // Handled by SongRow's nope animation
        } catch {
            showActionError(error.localizedDescription)
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

    func showActionError(_ message: String) {
        withAnimation {
            actionErrorMessage = message
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            withAnimation {
                if actionErrorMessage == message {
                    actionErrorMessage = nil
                }
            }
        }
    }
}
