import Foundation
import MusicKit
import SwiftUI
import Testing
@testable import ShflAppleMusic
@testable import ShflAppleMusicUI
@testable import ShflCore

@Suite("ArtworkPalette Tests")
@MainActor
struct ArtworkPaletteTests {
    @Test("Lists the artwork's background colour, then its text colours in order")
    func listsBackgroundThenTextColours() async throws {
        let artwork = try decodeArtwork(colors: """
            "bgColor": "ff0000",
            "textColor1": "00ff00",
            "textColor2": "0000ff",
            "textColor3": "ffffff",
            "textColor4": "000000",
            """)
        let palette = ArtworkPalette(store: store(serving: [.song(id: "1"): artwork]))

        let colors = try #require(await palette.colors(for: .song(id: "1")))

        #expect(colors.count == 5)
        #expect(colors.first.map(rgb) == rgb(.init(red: 1, green: 0, blue: 0)))
        #expect(colors.last.map(rgb) == rgb(.init(red: 0, green: 0, blue: 0)))
    }

    @Test("Leaves out colours MusicKit didn't report")
    func skipsMissingColours() async throws {
        let artwork = try decodeArtwork(colors: #""bgColor": "336699","#)
        let palette = ArtworkPalette(store: store(serving: [.playlist(id: "p"): artwork]))

        let colors = try #require(await palette.colors(for: .playlist(id: "p")))

        #expect(colors.count == 1)
    }

    @Test("Has no colours for a subject without artwork")
    func noArtworkMeansNoColours() async {
        let palette = ArtworkPalette(store: store(serving: [:]))

        let colors = await palette.colors(for: .artist(id: "missing"))

        #expect(colors == nil)
    }

    private func store(serving artwork: [ArtworkSubject: Artwork]) -> ArtworkStore {
        ArtworkStore(
            load: { subjects in artwork.filter { subjects.contains($0.key) } },
            pauseBetweenBatches: .zero
        )
    }

    private func decodeArtwork(colors: String) throws -> Artwork {
        let json = """
        {
          \(colors)
          "width": 100,
          "height": 100,
          "url": "https://example.com/{w}x{h}.jpg"
        }
        """
        return try JSONDecoder().decode(Artwork.self, from: Data(json.utf8))
    }

    private func rgb(_ color: Color) -> [Int] {
        let resolved = color.resolve(in: EnvironmentValues())
        return [resolved.red, resolved.green, resolved.blue].map { Int(($0 * 255).rounded()) }
    }
}
