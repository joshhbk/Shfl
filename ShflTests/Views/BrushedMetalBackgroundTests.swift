import SwiftUI
import Testing
@testable import Shfl

@Suite("BrushedMetalBackground Tests")
struct BrushedMetalBackgroundTests {

    @Test("ViewModel initialization with default values")
    func initialization() {
        let view = BrushedMetalBackground(baseColor: .gray)
        #expect(view.baseColor == .gray)
        #expect(view.intensity == 0.5)
        #expect(view.highlightOffset == .zero)
    }
}
