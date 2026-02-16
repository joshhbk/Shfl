import SwiftUI
import Testing
@testable import Shfl

@Suite("AlbumArtColorExtractor Tests")
struct AlbumArtColorExtractorTests {

    @Test("filters out colors below vibrancy threshold")
    func filtersLowVibrancy() {
        // Near-black: sat=0.5, bright=0.05 → score=0.025 (below 0.1)
        let dull = Color(hue: 0.5, saturation: 0.5, brightness: 0.05)
        // Near-gray: sat=0.05, bright=0.8 → score=0.04 (below 0.1)
        let gray = Color(hue: 0.0, saturation: 0.05, brightness: 0.8)

        let candidates: [(color: Color, label: String)] = [
            (dull, "dull"),
            (gray, "gray"),
        ]

        let result = AlbumArtColorExtractor.filterByVibrancy(candidates)
        #expect(result.count == 2)
    }

    @Test("keeps colors above vibrancy threshold")
    func keepsHighVibrancy() {
        // Vibrant blue: sat=0.8, bright=0.7 → score=0.56
        let vibrant = Color(hue: 0.6, saturation: 0.8, brightness: 0.7)

        let candidates: [(color: Color, label: String)] = [
            (vibrant, "vibrant"),
        ]

        let result = AlbumArtColorExtractor.filterByVibrancy(candidates)
        #expect(result.count == 1)
    }

    @Test("filters mixed candidates keeping only viable ones")
    func filtersMixedCandidates() {
        // Vibrant: sat=0.7, bright=0.8 → score=0.56 (above)
        let vibrant = Color(hue: 0.3, saturation: 0.7, brightness: 0.8)
        // Dull gray: sat=0.05, bright=0.9 → score=0.045 (below)
        let gray = Color(hue: 0.0, saturation: 0.05, brightness: 0.9)
        // Moderate: sat=0.4, bright=0.5 → score=0.2 (above)
        let moderate = Color(hue: 0.8, saturation: 0.4, brightness: 0.5)

        let candidates: [(color: Color, label: String)] = [
            (vibrant, "vibrant"),
            (gray, "gray"),
            (moderate, "moderate"),
        ]

        let result = AlbumArtColorExtractor.filterByVibrancy(candidates)
        #expect(result.count == 2)
    }

    @Test("returns empty array for empty input")
    func returnsEmptyForEmptyInput() {
        let result = AlbumArtColorExtractor.filterByVibrancy([])
        #expect(result.isEmpty)
    }

    @Test("color at exact threshold boundary is included")
    func boundaryThreshold() {
        // Exactly at threshold: sat=0.5, bright=0.2 → score=0.1
        let boundary = Color(hue: 0.5, saturation: 0.5, brightness: 0.2)

        let candidates: [(color: Color, label: String)] = [
            (boundary, "boundary"),
        ]

        let result = AlbumArtColorExtractor.filterByVibrancy(candidates)
        #expect(result.count == 1)
    }
}
