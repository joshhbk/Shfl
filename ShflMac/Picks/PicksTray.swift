import ShflAppleMusicUI
import ShflCore
import ShflDesign
import SwiftUI

/// Every slot in your picks, filled oldest first. VoiceOver reads it as the list of picks.
struct PicksTray: View {
    @State private var tones = TileTones()
    @State private var motion = TrayMotion()
    @State private var isShowingNoRoom = false
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
            Tray(capacity: draft.capacity, filled: draft.songCount, columns: Self.columns, marks: Set(TrayMarks.ruler(draft))) { index in
                switch slots[index] {
                case .picked(let song, let joinsNextShuffle):
                    PickedTile(tone: tones[song])
                        .tileRing(joinsNextShuffle)
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
            if isShowingNoRoom {
                Text(draft.isAtCapacity ? "Picks are full" : "Not enough room")
                    .font(.statusLabel)
                    .foregroundStyle(.warning)
                    .transition(.opacity)
            }
        }
        .task(id: draft.songs.map(\.id)) { await tones.load(draft.songs, using: store.map(ArtworkPalette.init)) }
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
