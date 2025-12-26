import SwiftUI

enum UndoAction: Equatable {
    case added
    case removed
}

struct UndoState: Equatable {
    let action: UndoAction
    let song: Song
    let timestamp: Date

    init(action: UndoAction, song: Song) {
        self.action = action
        self.song = song
        self.timestamp = Date()
    }
}

struct UndoPill: View {
    let state: UndoState
    let onUndo: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(Self.message(for: state.action, songTitle: state.song.title))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)

            Text("·")
                .foregroundStyle(.white.opacity(0.5))

            Button(action: onUndo) {
                Text("Undo")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.85))
        )
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Static Helpers (for testing)

    static func message(for action: UndoAction, songTitle: String) -> String {
        switch action {
        case .added:
            return "Added to Shfl"
        case .removed:
            return "Removed"
        }
    }
}

#Preview {
    ZStack {
        Color.gray.opacity(0.3)

        VStack {
            Spacer()
            UndoPill(
                state: UndoState(
                    action: .added,
                    song: Song(
                        id: "1",
                        title: "Bohemian Rhapsody",
                        artist: "Queen",
                        albumTitle: "A Night at the Opera",
                        artworkURL: nil
                    )
                ),
                onUndo: {},
                onDismiss: {}
            )
            .padding(.bottom, 32)
        }
    }
    .ignoresSafeArea()
}
