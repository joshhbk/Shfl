import SwiftUI
import Testing
@testable import ShflDesign

@Suite("Primitive metrics")
@MainActor
struct PrimitiveMetricsTests {
    @Test("Artwork rounds less as it gets smaller", arguments: [
        (ArtworkSize.hero, CornerRadius.card),
        (ArtworkSize.compact, CornerRadius.regular),
        (ArtworkSize.menuBar, CornerRadius.regular),
        (ArtworkSize.songRow, CornerRadius.tag),
        (ArtworkSize.listRow, CornerRadius.tile),
    ])
    func artworkRadius(size: CGFloat, radius: CGFloat) {
        #expect(ArtworkFrame<EmptyView>.cornerRadius(for: size) == radius)
    }

    @Test("Arrow keys walk the wheel's slots, and the opposite arrow returns to the centre")
    func wheelSlots() {
        #expect(ClickWheelSlot.center.moved(.upArrow) == .top)
        #expect(ClickWheelSlot.top.moved(.downArrow) == .center)
        #expect(ClickWheelSlot.leading.moved(.rightArrow) == .center)
        #expect(ClickWheelSlot.top.moved(.leftArrow) == .leading)
        #expect(ClickWheelSlot.bottom.moved(.upArrow) == .center)
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

    @Test("The scrubber's VoiceOver slider never gets a range or step that Slider traps on")
    func scrubberSliderInputs() {
        #expect(Scrubber.sliderStep(5, in: 0...1) == 1)
        #expect(Scrubber.sliderStep(5, in: 0...184) == 5)
        #expect(Scrubber.sliderRange(for: 0...0) == 0...1)
        #expect(Scrubber.sliderRange(for: 0...184) == 0...184)
    }

    @Test("Marquee text scrolls only when it overflows, at a steady speed")
    func marquee() {
        #expect(!MarqueeText.overflows(textWidth: 200, availableWidth: 200))
        #expect(MarqueeText.overflows(textWidth: 201, availableWidth: 200))
        #expect(!MarqueeText.overflows(textWidth: 500, availableWidth: 0))
        #expect(MarqueeText.scrollDuration(for: 300) == 10)
    }

    @Test("The scrubber fills in proportion, and stays empty for an empty range")
    func scrubberFraction() {
        #expect(Scrubber.fraction(of: 60, in: 10...110) == 0.5)
        #expect(Scrubber.fraction(of: 500, in: 10...110) == 1)
        #expect(Scrubber.fraction(of: 0, in: 0...0) == 0)
    }

    @Test("List columns keep fixed widths and share the rest between title and detail")
    func listColumnWidths() {
        let frames = ListColumns.columnFrames([.artwork, .title, .detail, .stat("plays", width: 64), .time, .accessory], in: 800)
        #expect(frames[.artwork] == 0...34)
        #expect(frames[.accessory]?.upperBound == 800)
        let title = frames[.title].map { $0.upperBound - $0.lowerBound } ?? 0
        let detail = frames[.detail].map { $0.upperBound - $0.lowerBound } ?? 0
        #expect(abs(title / detail - 1.6) < 0.001)
    }

    @Test("A list without a detail column gives its share to the title")
    func listColumnsWithoutDetail() {
        let frames = ListColumns.columnFrames([.artwork, .title, .stat("plays", width: 64), .time, .accessory], in: 500)
        #expect(frames[.detail] == nil)
        #expect(frames[.title] == CGFloat(46)...CGFloat(330))
    }

    @Test("Columns never get a negative width when the row is too narrow")
    func narrowListColumns() {
        let frames = ListColumns.columnFrames([.artwork, .title, .detail, .time, .accessory], in: 100)
        #expect(frames.values.allSatisfy { $0.upperBound >= $0.lowerBound })
    }
}
