import ShflAppleMusicUI
import ShflCore
import ShflDesign
import SwiftUI

/// Every slot in your picks, filled oldest first. VoiceOver reads it as the list of picks.
struct PicksTray: View {
    @State private var tones = TileTones()
    @Environment(DraftEditing.self) private var drafting
    @Environment(ListeningSessionHost.self) private var sessionHost
    @Environment(\.artworkStore) private var store

    var body: some View {
        let draft = drafting.draft
        let slots = TraySlots(
            picks: draft.songs,
            capacity: draft.capacity,
            milestones: draft.milestones,
            joiningNextShuffle: sessionHost.timeline.changes.joiningNextShuffle
        )
        Tray(capacity: draft.capacity, marks: Set(TrayMarks.ruler(draft))) { index in
            switch slots[index] {
            case .picked(let song, let joinsNextShuffle):
                PickedTile(tone: tones[song]).tileRing(joinsNextShuffle)
            case .empty(let isMilestone):
                EmptyTile().milestoneOutline(isMilestone)
            }
        }
        .task(id: draft.songs.map(\.id)) { await tones.load(draft.songs, using: store.map(ArtworkPalette.init)) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tray")
        .accessibilityChildren {
            ForEach(draft.songs.reversed()) { song in
                Text("\(song.title), \(song.artist)")
            }
        }
        .accessibilityIdentifier("mac.picks.tray")
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
