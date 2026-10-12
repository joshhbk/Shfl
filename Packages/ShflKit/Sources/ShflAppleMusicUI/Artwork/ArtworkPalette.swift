import MusicKit
import ShflAppleMusic
import ShflCore
import SwiftUI

public struct ArtworkPalette {
    let store: ArtworkStore

    public init(store: ArtworkStore) {
        self.store = store
    }

    /// MusicKit's colours for the artwork, or colours read from its image when MusicKit gives none, as it
    /// doesn't for library artwork on the Mac.
    public func colors(for subject: ArtworkSubject) async -> [Color]? {
        guard let artwork = await store.artwork(for: subject) else { return nil }
        let named = Self.colors(of: artwork)
        return named.isEmpty ? await Self.pixelColors(of: artwork) : named
    }

    /// Colours read from the artwork image itself, an 8 by 8 grid.
    public func pixelColors(for subject: ArtworkSubject) async -> [Color]? {
        guard let artwork = await store.artwork(for: subject) else { return nil }
        return await Self.pixelColors(of: artwork)
    }

    private static func pixelColors(of artwork: Artwork) async -> [Color]? {
        guard let url = artwork.url(width: 32, height: 32),
              let (data, _) = try? await URLSession.shared.data(from: url)
        else { return nil }
        return await Task.detached(priority: .utility) { ArtworkPixels.colors(in: data) }.value
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
