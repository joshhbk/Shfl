import Combine
import SwiftUI

@MainActor
final class SongUndoManager: ObservableObject {
    @Published private(set) var currentState: UndoState?
    private var dismissTask: Task<Void, Never>?

    func recordAction(_ action: UndoAction, song: Song, autoHideDelay: TimeInterval = 3.0) {
        dismissTask?.cancel()

        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            currentState = UndoState(action: action, song: song)
        }

        dismissTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(autoHideDelay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            dismiss()
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) {
            currentState = nil
        }
    }
}
