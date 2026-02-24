import SwiftUI

struct SongRow: View, Equatable {
    let song: Song
    let isSelected: Bool
    let isAtCapacity: Bool
    let onToggle: () -> Void

    @Environment(\.shuffleTheme) private var theme

    @State private var showNope = false
    @State private var showGlow = false
    @State private var checkmarkBounce = false
    @State private var nopeTask: Task<Void, Never>?
    @State private var glowTask: Task<Void, Never>?
    @State private var bounceTask: Task<Void, Never>?

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
                    .foregroundStyle(isSelected ? theme.accentColor : .gray.opacity(0.3))
                    .scaleEffect(checkmarkBounce ? 1.2 : 1.0)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .background(isSelected ? theme.accentColor.opacity(0.15) : Color.clear)
            .overlay(
                theme.accentColor.opacity(showGlow ? 0.15 : 0)
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
            nopeTask?.cancel()
            nopeTask = Task {
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
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
            glowTask?.cancel()
            glowTask = Task {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                showGlow = false
            }

            // Checkmark bounce on add
            withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                checkmarkBounce = true
            }
            bounceTask?.cancel()
            bounceTask = Task {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                    checkmarkBounce = false
                }
            }
        }

        onToggle()
    }

    // MARK: - Static Helpers (for testing)

    static func rowOpacity(isSelected: Bool, isAtCapacity: Bool) -> Double {
        if isAtCapacity && !isSelected {
            return 0.5
        }
        return 1.0
    }
}

#Preview("All Themes — Light") {
    ScrollView {
        ForEach(ShuffleTheme.allThemes) { theme in
            VStack(alignment: .leading, spacing: 0) {
                Text(theme.name)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 4)

                SongRow(
                    song: Song(id: "1", title: "Bohemian Rhapsody", artist: "Queen", albumTitle: "A Night at the Opera", artworkURL: nil),
                    isSelected: true,
                    onToggle: {}
                )
                Divider().padding(.leading, 72)
                SongRow(
                    song: Song(id: "2", title: "Stairway to Heaven", artist: "Led Zeppelin", albumTitle: "Led Zeppelin IV", artworkURL: nil),
                    isSelected: false,
                    onToggle: {}
                )
            }
            .environment(\.shuffleTheme, theme)
        }
    }
    .preferredColorScheme(.light)
}

#Preview("All Themes — Dark") {
    ScrollView {
        ForEach(ShuffleTheme.allThemes) { theme in
            VStack(alignment: .leading, spacing: 0) {
                Text(theme.name)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 4)

                SongRow(
                    song: Song(id: "1", title: "Bohemian Rhapsody", artist: "Queen", albumTitle: "A Night at the Opera", artworkURL: nil),
                    isSelected: true,
                    onToggle: {}
                )
                Divider().padding(.leading, 72)
                SongRow(
                    song: Song(id: "2", title: "Stairway to Heaven", artist: "Led Zeppelin", albumTitle: "Led Zeppelin IV", artworkURL: nil),
                    isSelected: false,
                    onToggle: {}
                )
            }
            .environment(\.shuffleTheme, theme)
        }
    }
    .preferredColorScheme(.dark)
}
