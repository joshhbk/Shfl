import SwiftUI

struct SongRow: View, Equatable {
    let song: Song
    let isSelected: Bool
    let isAtCapacity: Bool
    let onToggle: () -> Void

    @State private var showNope = false
    @State private var showGlow = false
    @State private var checkmarkBounce = false

    // Equatable - ignore closure, compare only data that affects rendering
    static func == (lhs: SongRow, rhs: SongRow) -> Bool {
        lhs.song.id == rhs.song.id &&
        lhs.isSelected == rhs.isSelected &&
        lhs.isAtCapacity == rhs.isAtCapacity
    }

    init(
        song: Song,
        isSelected: Bool,
        isAtCapacity: Bool = false,
        onToggle: @escaping () -> Void
    ) {
        self.song = song
        self.isSelected = isSelected
        self.isAtCapacity = isAtCapacity
        self.onToggle = onToggle
    }

    var body: some View {
        Button(action: handleTap) {
            HStack(spacing: 12) {
                SongDisplay(song: song)

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isSelected ? .blue : .gray.opacity(0.3))
                    .scaleEffect(checkmarkBounce ? 1.2 : 1.0)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .background(Self.backgroundColor(isSelected: isSelected))
            .overlay(
                Color.blue.opacity(showGlow ? 0.15 : 0)
                    .animation(.easeOut(duration: 0.4), value: showGlow)
            )
            .contentShape(Rectangle())
            .opacity(Self.rowOpacity(isSelected: isSelected, isAtCapacity: isAtCapacity))
            .offset(x: showNope ? -8 : 0)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isSelected)
        .animation(.default, value: showNope)
    }

    private func handleTap() {
        if !isSelected && isAtCapacity {
            // "Nope" bounce animation
            HapticFeedback.warning.trigger()
            withAnimation(.easeInOut(duration: 0.05).repeatCount(3, autoreverses: true)) {
                showNope = true
            }
            Task {
                try? await Task.sleep(for: .milliseconds(150))
                showNope = false
            }
            return
        }

        // Fire haptic immediately on tap
        if isSelected {
            HapticFeedback.light.trigger()
        } else {
            HapticFeedback.medium.trigger()

            // Glow flash on add
            showGlow = true
            Task {
                try? await Task.sleep(for: .milliseconds(300))
                showGlow = false
            }

            // Checkmark bounce on add
            withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                checkmarkBounce = true
            }
            Task {
                try? await Task.sleep(for: .milliseconds(200))
                withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                    checkmarkBounce = false
                }
            }
        }

        onToggle()
    }

    // MARK: - Static Helpers (for testing)

    static func backgroundColor(isSelected: Bool) -> Color {
        isSelected ? Color.blue.opacity(0.08) : Color.clear
    }

    static func rowOpacity(isSelected: Bool, isAtCapacity: Bool) -> Double {
        if isAtCapacity && !isSelected {
            return 0.5
        }
        return 1.0
    }
}

#Preview {
    VStack(spacing: 0) {
        SongRow(
            song: Song(id: "1", title: "Bohemian Rhapsody", artist: "Queen", albumTitle: "A Night at the Opera", artworkURL: nil),
            isSelected: false,
            onToggle: {}
        )
        Divider()
        SongRow(
            song: Song(id: "2", title: "Stairway to Heaven", artist: "Led Zeppelin", albumTitle: "Led Zeppelin IV", artworkURL: nil),
            isSelected: true,
            onToggle: {}
        )
        Divider()
        SongRow(
            song: Song(id: "3", title: "Hotel California", artist: "Eagles", albumTitle: "Hotel California", artworkURL: nil),
            isSelected: false,
            isAtCapacity: true,
            onToggle: {}
        )
    }
}
