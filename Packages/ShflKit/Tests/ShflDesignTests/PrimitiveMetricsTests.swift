import SwiftUI
import Testing
@testable import ShflDesign

@Suite("Primitive metrics")
@MainActor
struct PrimitiveMetricsTests {
    @Test("Artwork rounds less as it gets smaller", arguments: [
        (ArtworkSize.hero, CornerRadius.card),
        (ArtworkSize.miniPlayer, CornerRadius.card),
        (ArtworkSize.compact, CornerRadius.regular),
        (ArtworkSize.menuBar, CornerRadius.regular),
        (ArtworkSize.row, CornerRadius.tag),
        (ArtworkSize.listRow, CornerRadius.tile),
    ])
    func artworkRadius(size: CGFloat, radius: CGFloat) {
        #expect(ArtworkFrame<EmptyView>.cornerRadius(for: size) == radius)
    }

    @Test("Text buttons take their height and type from the control size")
    func textButtonMetrics() {
        #expect(TextButtonMetrics(.small).height == 30)
        #expect(TextButtonMetrics(.regular).height == 38)
        #expect(TextButtonMetrics(.large).height == 44)
    }

    @Test("The scrubber maps a drag across its width onto its range, clamped at both ends")
    func scrubberValue() {
        let bounds = 10.0...110.0
        #expect(Scrubber.value(at: 0, width: 200, in: bounds) == 10)
        #expect(Scrubber.value(at: 100, width: 200, in: bounds) == 60)
        #expect(Scrubber.value(at: -30, width: 200, in: bounds) == 10)
        #expect(Scrubber.value(at: 260, width: 200, in: bounds) == 110)
        #expect(Scrubber.value(at: 50, width: 0, in: bounds) == 10)
    }

    @Test("The scrubber fills in proportion, and stays empty for an empty range")
    func scrubberFraction() {
        #expect(Scrubber.fraction(of: 60, in: 10...110) == 0.5)
        #expect(Scrubber.fraction(of: 500, in: 10...110) == 1)
        #expect(Scrubber.fraction(of: 0, in: 0...0) == 0)
    }
}
