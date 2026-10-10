import MusicKit
import ShflCore
import SwiftUI

/// The colours Apple Music picked for a library item's artwork.
struct ArtworkPalette {
    let store: ArtworkStore

    /// Every colour MusicKit reports for the subject's artwork — background,
    /// then primary through quaternary text — or nil when the subject has no
    /// artwork or it couldn't be looked up.
    func colors(for subject: ArtworkSubject) async -> [Color]? {
        guard let artwork = await store.artwork(for: subject) else { return nil }
        return Self.colors(of: artwork)
    }

    private static func colors(of artwork: Artwork) -> [Color] {
        [
            artwork.backgroundColor,
            artwork.primaryTextColor,
            artwork.secondaryTextColor,
            artwork.tertiaryTextColor,
            artwork.quaternaryTextColor
        ]
        .compactMap { $0.map { Color(cgColor: $0) } }
    }
}
