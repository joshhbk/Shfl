import CoreFoundation
import Testing
@testable import Shfl

@Suite("MotionManager Tests")
struct MotionManagerTests {

    @Test("Initial pitch and roll are zero")
    func initialValuesAreZero() {
        let manager = MotionManager()
        #expect(manager.pitch == 0)
        #expect(manager.roll == 0)
    }

    @Test("Highlight offset calculation maps tilt to offset")
    func highlightOffsetCalculation() {
        // With sensitivity 1.0, max tilt should give max offset
        let offset = MotionManager.highlightOffset(
            pitch: 0.5,  // ~28 degrees
            roll: 0.3,
            sensitivity: 1.0,
            maxOffset: 50
        )
        #expect(offset.x != 0 || offset.y != 0, "Should produce non-zero offset")
    }

    @Test("Zero sensitivity produces zero offset")
    func zeroSensitivityProducesZeroOffset() {
        let offset = MotionManager.highlightOffset(
            pitch: 0.5,
            roll: 0.5,
            sensitivity: 0,
            maxOffset: 50
        )
        #expect(offset.x == 0 && offset.y == 0)
    }
}
