import Foundation
import Testing
@testable import Shfl

@Suite("CapacityProgressBar Tests")
struct CapacityProgressBarTests {
    @Test("Progress is calculated correctly at midpoint")
    func testProgressCalculation() {
        let progress = CapacityProgressBar.calculateProgress(current: 60, maximum: 120)
        #expect(abs(progress - 0.5) < 0.001)
    }

    @Test("Progress is zero when current is zero")
    func testProgressAtZero() {
        let progress = CapacityProgressBar.calculateProgress(current: 0, maximum: 120)
        #expect(abs(progress - 0.0) < 0.001)
    }

    @Test("Progress is 1.0 when at full capacity")
    func testProgressAtFull() {
        let progress = CapacityProgressBar.calculateProgress(current: 120, maximum: 120)
        #expect(abs(progress - 1.0) < 0.001)
    }

    @Test("Progress handles zero maximum gracefully")
    func testProgressWithZeroMaximum() {
        let progress = CapacityProgressBar.calculateProgress(current: 10, maximum: 0)
        #expect(progress == 0.0)
    }

    @Test("Milestones are correctly identified")
    func testMilestoneDetection() {
        #expect(CapacityProgressBar.isMilestone(1))
        #expect(CapacityProgressBar.isMilestone(50))
        #expect(CapacityProgressBar.isMilestone(100))
        #expect(CapacityProgressBar.isMilestone(120))
        #expect(!CapacityProgressBar.isMilestone(42))
        #expect(!CapacityProgressBar.isMilestone(0))
        #expect(!CapacityProgressBar.isMilestone(75))
    }
}
