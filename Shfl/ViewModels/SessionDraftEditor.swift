import SwiftUI

/// Owns the picker's edit surface over the session draft: membership, capacity
/// and undo.
///
/// Membership is read straight from the player's `SessionDraft`, so there is a
/// single source of truth. This module never keeps a second copy of the
/// selected song IDs; every mutation is a draft write, and the derived
/// `selectedSongIds` follows it.
@Observable
@MainActor
final class SessionDraftEditor {
    @ObservationIgnored private let player: ShufflePlayer
    @ObservationIgnored private let addSongs: @MainActor ([Song]) async throws -> Void
    @ObservationIgnored private let removeSong: @MainActor (String) async -> Void
    @ObservationIgnored private let removeAllSongs: @MainActor () async -> Void
    @ObservationIgnored private let undoManager: SongUndoManager

    private(set) var actionErrorMessage: String?
    private(set) var autofillIsExhausted = false

    init(
        player: ShufflePlayer,
        addSongs: @escaping @MainActor ([Song]) async throws -> Void,
        removeSong: @escaping @MainActor (String) async -> Void,
        removeAllSongs: @escaping @MainActor () async -> Void,
        undoManager: SongUndoManager? = nil
    ) {
        self.player = player
        self.addSongs = addSongs
        self.removeSong = removeSong
        self.removeAllSongs = removeAllSongs
        self.undoManager = undoManager ?? SongUndoManager()
    }

    // MARK: - Membership & capacity (derived from the draft)

    var selectedSongIds: Set<String> {
        Set(player.draft.songs.map(\.id))
    }

    func contains(_ songID: String) -> Bool {
        player.containsSong(id: songID)
    }

    var songCount: Int { player.songCount }
    var capacity: Int { player.capacity }
    var remainingCapacity: Int { player.remainingCapacity }
    var isAtCapacity: Bool { player.remainingCapacity == 0 }

    // MARK: - Undo

    var undoState: UndoState? { undoManager.currentState }

    func dismissUndo() {
        undoManager.dismiss()
    }

    // MARK: - Editing

    func toggle(_ song: Song) {
        autofillIsExhausted = false

        if contains(song.id) {
            Task { @MainActor in await removeSong(song.id) }
            undoManager.recordAction(.removed, song: song)
        } else {
            Task { @MainActor in
                do {
                    try await addSongs([song])
                    undoManager.recordAction(.added, song: song)

                    if CapacityProgressBar.isMilestone(songCount) {
                        HapticFeedback.milestone.trigger()
                    }
                } catch ShufflePlayerError.capacityReached {
                    // Handled by SongRow's nope animation
                } catch {
                    showActionError(error.localizedDescription)
                }
            }
        }
    }

    /// Adds songs to the draft through the same write port as every other
    /// edit, so bulk edits (autofill) cannot bypass membership bookkeeping.
    func add(_ songs: [Song]) async throws {
        try await addSongs(songs)
    }

    func undo(_ state: UndoState) {
        autofillIsExhausted = false

        switch state.action {
        case .added:
            Task { @MainActor in await removeSong(state.song.id) }
            HapticFeedback.light.trigger()
        case .removed:
            Task { @MainActor in
                try? await addSongs([state.song])
                HapticFeedback.medium.trigger()
            }
        }

        undoManager.dismiss()
    }

    func clearAll() {
        autofillIsExhausted = false
        undoManager.dismiss()
        Task { @MainActor in await removeAllSongs() }
    }

    /// Reconciles autofill exhaustion with the post-autofill draft. Delegating
    /// to `remainingCapacity` means the flag can never disagree with membership.
    func noteAutofillCompleted(addedCount: Int, requestedCount: Int) {
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