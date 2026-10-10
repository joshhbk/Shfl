import Foundation

public enum DraftEdit: Equatable {
    case added(songCount: Int, reachedMilestone: Bool)
    case removed
    case rejectedAtCapacity
    case failed(String)
}

@Observable
@MainActor
public final class SessionDraftEditor {
    deinit {} // Keep nonisolated: Xcode 27 synthesizes an isolated one that can crash on release. See ViewTeardownTests.
    public private(set) var actionErrorMessage: String?
    public private(set) var autofillIsExhausted = false

    public init() {}

    // MARK: - Editing

    @discardableResult
    public func toggle(_ song: Song, in draft: SessionDraftStore) -> DraftEdit {
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

    public func clearAll(in draft: SessionDraftStore) {
        autofillIsExhausted = false
        draft.removeAll()
    }

    public func noteAutofillCompleted(addedCount: Int, requestedCount: Int, remainingCapacity: Int) {
        autofillIsExhausted = addedCount < requestedCount && remainingCapacity > 0
    }

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
