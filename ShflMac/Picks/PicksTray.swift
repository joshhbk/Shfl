import ShflAppleMusicUI
import ShflCore
import ShflDesign
import SwiftUI

/// Every slot in your picks, filled oldest first. One Tab stop: arrow keys walk the picks and ⌫ removes one.
/// VoiceOver reads it as the list of picks.
struct PicksTray: View {
    @State private var tones = TileTones()
    @State private var motion = TrayMotion()
    @State private var isShowingNoRoom = false
    @State private var cursor: TrayCursor?
    @FocusState private var isFocused: Bool
    @Environment(DraftEditing.self) private var drafting
    @Environment(ListeningSessionHost.self) private var sessionHost
    @Environment(\.artworkStore) private var store

    private static let columns = 10

    var body: some View {
        let draft = drafting.draft
        let slots = TraySlots(
            picks: draft.songs,
            capacity: draft.capacity,
            milestones: draft.milestones,
            joiningNextShuffle: sessionHost.timeline.changes.joiningNextShuffle
        )
        VStack(alignment: .leading, spacing: Spacing.s8) {
            Tray(capacity: draft.capacity, columns: Self.columns) { index in
                switch slots[index] {
                case .picked(let song, let joinsNextShuffle):
                    PickedTile(tone: tones[song])
                        .tileRing(joinsNextShuffle)
                        .tileFocus(isFocused && cursor?.index == index)
                        .tilePulse(
                            trigger: motion.milestoneBeats,
                            delay: motion.pulseDelay(for: index, capacity: draft.capacity, columns: Self.columns)
                        )
                case .empty(let isMilestone):
                    EmptyTile()
                        .milestoneOutline(isMilestone)
                        .slotWarning(trigger: motion.noRoomFlashes)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Tray")
            .accessibilityChildren {
                ForEach(draft.songs.reversed()) { song in
                    Text("\(song.title), \(song.artist)")
                }
            }
            .accessibilityIdentifier("mac.picks.tray")
            .focusable(interactions: .edit)
            .focused($isFocused)
            .focusEffectDisabled()
            .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { press in
                move(press.key)
                return .handled
            }
            .onDeleteCommand(perform: removeFocusedPick)
            .onChange(of: isFocused) { _, focused in
                cursor = focused ? TrayCursor(count: draft.songCount) : nil
            }
            if isShowingNoRoom {
                Text(draft.isAtCapacity ? "Picks are full" : "Not enough room")
                    .font(.statusLabel)
                    .foregroundStyle(.warning)
                    .transition(.opacity)
            } else if isFocused, let cursor, draft.songs.indices.contains(cursor.index) {
                let song = draft.songs[cursor.index]
                Text("\(song.title) · \(song.artist)")
                    .font(.statusLine)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .accessibilityHidden(true)
            }
        }
        .onChange(of: draft.songs.map(\.id), initial: true) {
            tones.load(draft.songs, using: store.map(ArtworkPalette.init))
        }
        .onChange(of: drafting.moment) { _, moment in
            if let moment { motion.play(moment.kind) }
        }
        .task(id: motion.noRoomFlashes) {
            guard motion.noRoomFlashes > 0 else { return }
            withAnimation { isShowingNoRoom = true }
            try? await Task.sleep(for: .seconds(3))
            withAnimation { isShowingNoRoom = false }
        }
    }
}

private extension PicksTray {
    func move(_ key: KeyEquivalent) {
        let step: TrayCursor.Step = switch key {
        case .leftArrow: .left
        case .rightArrow: .right
        case .upArrow: .up
        default: .down
        }
        cursor?.move(step, count: drafting.draft.songCount, columns: Self.columns)
    }

    func removeFocusedPick() {
        let songs = drafting.draft.songs
        guard let cursor, songs.indices.contains(cursor.index) else { return }
        drafting.remove([songs[cursor.index]])
        self.cursor = cursor.clamped(to: drafting.draft.songCount)
    }
}

/// The three newest picks under the tray.
struct LatestPicks: View {
    @Environment(DraftEditing.self) private var drafting

    var body: some View {
        let latest = drafting.draft.songs.suffix(3).reversed()
        if !latest.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("Latest picks")
                    .font(.columnLabel)
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, Spacing.s4)
                ForEach(latest) { song in
                    PickRow(song: song)
                }
            }
        }
    }
}
