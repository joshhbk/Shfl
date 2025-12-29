import Foundation
import Testing
@testable import Shfl

@Suite("ShuffleAlgorithm Tests")
struct ShuffleAlgorithmTests {
    @Test("All cases count equals 5")
    func allCasesCount() {
        #expect(ShuffleAlgorithm.allCases.count == 5)
    }

    @Test("Display names are correct")
    func displayNames() {
        #expect(ShuffleAlgorithm.pureRandom.displayName == "Pure Random")
        #expect(ShuffleAlgorithm.noRepeat.displayName == "Full Shuffle")
        #expect(ShuffleAlgorithm.weightedByRecency.displayName == "Least Recent")
        #expect(ShuffleAlgorithm.weightedByPlayCount.displayName == "Least Played")
        #expect(ShuffleAlgorithm.artistSpacing.displayName == "Artist Spacing")
    }

    @Test("Raw values are correct")
    func rawValues() {
        #expect(ShuffleAlgorithm.pureRandom.rawValue == "pureRandom")
        #expect(ShuffleAlgorithm.noRepeat.rawValue == "noRepeat")
        #expect(ShuffleAlgorithm.weightedByRecency.rawValue == "weightedByRecency")
        #expect(ShuffleAlgorithm.weightedByPlayCount.rawValue == "weightedByPlayCount")
        #expect(ShuffleAlgorithm.artistSpacing.rawValue == "artistSpacing")
    }

    @Test("Descriptions contain expected keywords")
    func descriptions() {
        #expect(ShuffleAlgorithm.pureRandom.description.contains("randomly"))
        #expect(ShuffleAlgorithm.noRepeat.description.contains("every song"))
        #expect(ShuffleAlgorithm.weightedByRecency.description.contains("recently"))
        #expect(ShuffleAlgorithm.weightedByPlayCount.description.contains("fewer plays"))
        #expect(ShuffleAlgorithm.artistSpacing.description.contains("artist"))
    }
}
