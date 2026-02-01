import SwiftUI
import Testing
@testable import Shfl

@Suite("BrushedMetalBackground Tests")
struct BrushedMetalBackgroundTests {

    @Test("View initialization with highlight offset")
    func initialization() {
        let offset = CGPoint(x: 10, y: 20)
        let view = BrushedMetalBackground(highlightOffset: offset)
        #expect(view.highlightOffset == offset)
    }

    @Test("View initialization with zero offset")
    func initializationWithZeroOffset() {
        let view = BrushedMetalBackground(highlightOffset: .zero)
        #expect(view.highlightOffset == .zero)
    }
}
