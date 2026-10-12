import SwiftUI
import Testing
@testable import ShflDesign

@Suite("Tile tone")
struct TileToneTests {
    let orange = Color.Resolved(hex: 0xF28B30)
    let black = Color.Resolved(hex: 0x000000)

    @Test("A cover that's mostly one strong colour tiles in that colour")
    func strongColourWins() throws {
        let tone = try #require(ArtworkTone.tile(from: Array(repeating: orange, count: 48) + Array(repeating: black, count: 16)))
        #expect(abs(tone.red - orange.red) < 0.02)
        #expect(abs(tone.green - orange.green) < 0.02)
        #expect(abs(tone.blue - orange.blue) < 0.02)
    }

    @Test("A grey cover tiles in its average")
    func greysAverage() throws {
        let light = Color.Resolved(hex: 0xDDDDDD)
        let dark = Color.Resolved(hex: 0x333333)
        let tone = try #require(ArtworkTone.tile(from: [light, dark]))
        #expect(abs(tone.red - (light.red + dark.red) / 2) < 0.01)
        #expect(abs(tone.red - tone.blue) < 0.001)
    }

    @Test("No colours, no tone")
    func empty() {
        #expect(ArtworkTone.tile(from: []) == nil)
    }
}
