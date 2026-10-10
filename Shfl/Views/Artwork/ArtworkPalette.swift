import MusicKit
import ShflCore
import SwiftUI

struct ArtworkPalette {
    let store: ArtworkStore

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
