import Foundation
import SwiftUI
import Testing
@testable import Shfl

@Suite("SongRow Tests")
struct SongRowTests {
    @Test("Disabled opacity is 0.5 when at capacity and not selected")
    func testDisabledOpacityAtCapacity() {
        #expect(SongRow.rowOpacity(isSelected: false, isAtCapacity: true) == 0.5)
    }

    @Test("Opacity is 1.0 when selected even at capacity")
    func testSelectedOpacityAtCapacity() {
        #expect(SongRow.rowOpacity(isSelected: true, isAtCapacity: true) == 1.0)
    }

    @Test("Opacity is 1.0 when not at capacity")
    func testOpacityNotAtCapacity() {
        #expect(SongRow.rowOpacity(isSelected: false, isAtCapacity: false) == 1.0)
    }
}
