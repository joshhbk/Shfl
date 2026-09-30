import SwiftUI

/// The picker's editing state around the session draft: undo, the action
/// error banner, and whether autofill has run out of songs.
///
/// Membership and capacity are read from `SessionDraftStore`; this module
/// never keeps its own copy. Every edit is a direct store write.
@Observable
@MainActor
final class SessionDraftEditor {
    deinit {} // Keep nonisolated: Xcode 27 synthesizes an isolated one that can crash on release. See ViewTeardownTests.
    @ObservationIgnored private let undoManager: SongUndoManager

    private(set) var actionErrorMessage: String?
    private(set) var autofillIsExhausted = false

    init(undoManager: SongUndoManager? = nil) {
        self.undoManager = undoManager ?? SongUndoManager()
    }

    // MARK: - Undo

    var undoState: UndoState? { undoManager.currentState }

    func dismissUndo() {
        undoManager.dismiss()
    }

    // MARK: - Editing

    func toggle(_ song: Song, in draft: SessionDraftStore) {
        autofillIsExhausted = false

        if draft.contains(song.id) {
            draft.remove(songID: song.id)
            undoManager.recordAction(.removed, song: song)
            return
        }

        do {
            try draft.add(song)
            undoManager.recordAction(.added, song: song)
            if CapacityProgressBar.isMilestone(draft.songCount) {
                HapticFeedback.milestone.trigger()
            }
        } catch ShufflePlayerError.capacityReached {
            // Handled by SongRow's nope animation
        } catch {
            showActionError(error.localizedDescription)
        }
    }

    func undo(_ state: UndoState, in draft: SessionDraftStore) {
        autofillIsExhausted = false

        switch state.action {
        case .added:
            draft.remove(songID: state.song.id)
            HapticFeedback.light.trigger()
        case .removed:
            try? draft.add(state.song)
            HapticFeedback.medium.trigger()
        }

        undoManager.dismiss()
    }

    func clearAll(in draft: SessionDraftStore) {
        autofillIsExhausted = false
        undoManager.dismiss()
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
