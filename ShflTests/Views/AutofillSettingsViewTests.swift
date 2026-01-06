import SwiftUI
import Testing
@testable import Shfl

@Suite("AutofillSettingsView Tests")
struct AutofillSettingsViewTests {
    @Test("Default algorithm is random")
    func defaultAlgorithmIsRandom() {
        // Clear any existing value
        UserDefaults.standard.removeObject(forKey: "autofillAlgorithm")

        let storedValue = UserDefaults.standard.string(forKey: "autofillAlgorithm")
        #expect(storedValue == nil, "No value should be stored by default")

        // The view should default to random when nil
        let algorithm = AutofillAlgorithm(rawValue: storedValue ?? "random")
        #expect(algorithm == .random)
    }

    @Test("Algorithm enum has correct display names")
    func algorithmDisplayNames() {
        #expect(AutofillAlgorithm.random.displayName == "Random")
        #expect(AutofillAlgorithm.recentlyAdded.displayName == "Recently Added")
    }

    @Test("Algorithm enum has all expected cases")
    func algorithmCases() {
        let cases = AutofillAlgorithm.allCases
        #expect(cases.count == 2)
        #expect(cases.contains(.random))
        #expect(cases.contains(.recentlyAdded))
    }

    @Test("Algorithm raw values are stable")
    func algorithmRawValues() {
        #expect(AutofillAlgorithm.random.rawValue == "random")
        #expect(AutofillAlgorithm.recentlyAdded.rawValue == "recentlyAdded")
    }
}
