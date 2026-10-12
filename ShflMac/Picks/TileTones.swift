import ShflAppleMusicUI
import ShflCore
import ShflDesign
import SwiftUI

/// Each picked song's tile colour, read from its artwork once.
@Observable
@MainActor
final class TileTones {
    deinit {} // Keep nonisolated: Xcode 27 synthesizes an isolated one that can crash on release. See ViewTeardownTests.

    private var tones: [String: Color] = [:]
    @ObservationIgnored private var requested: Set<String> = []

    subscript(song: Song) -> Color? { tones[song.id] }

    // Each load outlives the view's update, so editing picks mid-load can't leave a song uncoloured.
    func load(_ songs: [Song], using palette: ArtworkPalette?) {
        guard let palette else { return }
        for id in songs.map(\.id) where !requested.contains(id) {
            requested.insert(id)
            Task { [weak self] in
                let colors = await palette.pixelColors(for: .song(id: id)) ?? []
                let tone = ArtworkTone.tile(from: colors.map { $0.resolve(in: EnvironmentValues()) })
                self?.tones[id] = tone.map(Color.init)
            }
        }
    }
}
