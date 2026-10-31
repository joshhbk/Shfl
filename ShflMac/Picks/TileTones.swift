import ShflAppleMusicUI
import ShflCore
import SwiftUI

/// Each picked song's artwork colour for its tray tile, loaded once per song.
@Observable
@MainActor
final class TileTones {
    deinit {} // Keep nonisolated: Xcode 27 synthesizes an isolated one that can crash on release. See ViewTeardownTests.

    private var tones: [String: Color] = [:]
    @ObservationIgnored private var requested: Set<String> = []

    subscript(song: Song) -> Color? { tones[song.id] }

    func load(_ songs: [Song], using palette: ArtworkPalette?) async {
        guard let palette else { return }
        let missing = songs.map(\.id).filter { !requested.contains($0) }
        requested.formUnion(missing)
        await withTaskGroup(of: (String, Color?).self) { group in
            for id in missing {
                group.addTask { @MainActor in (id, await palette.colors(for: .song(id: id))?.first) }
            }
            for await (id, tone) in group {
                tones[id] = tone
            }
        }
    }
}
