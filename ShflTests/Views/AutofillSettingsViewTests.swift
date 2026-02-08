import Foundation
import SwiftUI
import Testing
@testable import Shfl

@Suite("AutofillSettingsView Tests")
struct AutofillSettingsViewTests {
    @Test("Default algorithm is random")
    @MainActor
    func defaultAlgorithmIsRandom() {
        let suite = "AutofillSettingsViewTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            Issue.record("Failed to create isolated UserDefaults suite")
            return
        }

        let settings = AppSettings(defaults: defaults)
        #expect(settings.autofillAlgorithm == .random)
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
