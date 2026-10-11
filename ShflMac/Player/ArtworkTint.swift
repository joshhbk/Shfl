import ShflAppleMusicUI
import ShflCore
import ShflDesign
import SwiftUI

extension View {
    /// Tints the player body with the darkest strong colour of `song`'s artwork.
    func tintedByArtwork(of song: Song?) -> some View {
        modifier(ArtworkTintModifier(songID: song?.id))
    }
}

private struct ArtworkTintModifier: ViewModifier {
    let songID: String?

    @Environment(\.artworkStore) private var store
    @State private var tone: Color.Resolved?

    func body(content: Content) -> some View {
        content
            .artworkTint(tone)
            .animation(.easeInOut(duration: 0.4), value: tone)
            .task(id: songID) {
                guard let songID, let store else {
                    tone = nil
                    return
                }
                let colors = await ArtworkPalette(store: store).colors(for: .song(id: songID)) ?? []
                tone = ArtworkTone.pick(from: colors.map { $0.resolve(in: EnvironmentValues()) })
            }
    }
}
