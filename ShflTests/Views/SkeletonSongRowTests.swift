import Foundation
import Testing
@testable import Shfl

@Suite("SkeletonSongRow Tests")
struct SkeletonSongRowTests {

    @Test("Skeleton row can be instantiated")
    func testSkeletonRowInstantiation() {
        // SkeletonSongRow should match SongRow layout
        // This is a structural test - the component exists and renders
        let row = SkeletonSongRow()
        #expect(row.animate == true)
    }

    @Test("Shimmer effect defaults to true")
    func testShimmerEffectDefaultsToTrue() {
        let row = SkeletonSongRow()
        #expect(row.animate == true)
    }

    @Test("Shimmer effect can be disabled")
    func testShimmerEffectCanBeDisabled() {
        let row = SkeletonSongRow(animate: false)
        #expect(row.animate == false)
    }
}
