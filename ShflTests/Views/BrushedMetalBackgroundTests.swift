import SwiftUI
import Testing
@testable import Shfl

@Suite("BrushedMetalBackground Tests")
struct BrushedMetalBackgroundTests {

    @Test("Ring count calculation returns expected rings for size")
    func ringCountForSize() {
        // 200pt radius with 2pt spacing = 100 rings
        let count = BrushedMetalBackground.ringCount(for: 200, spacing: 2)
        #expect(count == 100)
    }

    @Test("Ring opacity alternates between light and dark")
    func ringOpacityAlternates() {
        let opacity0 = BrushedMetalBackground.ringOpacity(at: 0, intensity: 1.0)
        let opacity1 = BrushedMetalBackground.ringOpacity(at: 1, intensity: 1.0)
        #expect(opacity0 != opacity1, "Adjacent rings should have different opacity")
    }

    @Test("Zero intensity returns zero opacity")
    func zeroIntensityReturnsZero() {
        let opacity = BrushedMetalBackground.ringOpacity(at: 0, intensity: 0.0)
        #expect(opacity == 0.0)
    }

    @Test("Highlight gradient center offset responds to input")
    func highlightGradientOffset() {
        let offset = CGPoint(x: 20, y: -10)
        let center = CGPoint(x: 200, y: 300)
        let result = BrushedMetalBackground.highlightCenter(base: center, offset: offset)
        #expect(result.x == 220)
        #expect(result.y == 290)
    }
}
