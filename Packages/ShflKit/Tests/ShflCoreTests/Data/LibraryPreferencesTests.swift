import XCTest
@testable import ShflCore

@MainActor
final class LibraryPreferencesTests: XCTestCase {
    private let suiteName = "LibraryPreferencesTests"

    override func tearDown() {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testDefaultsToMostPlayedAndRandomAutofill() throws {
        let preferences = LibraryPreferences(defaults: try XCTUnwrap(UserDefaults(suiteName: suiteName)))

        XCTAssertEqual(preferences.sortOption, .mostPlayed)
        XCTAssertEqual(preferences.autofillAlgorithm, .random)
    }

    func testChangesAreSavedUnderTheExistingKeys() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let preferences = LibraryPreferences(defaults: defaults)

        preferences.sortOption = .alphabetical
        preferences.autofillAlgorithm = .recentlyAdded

        XCTAssertEqual(defaults.string(forKey: "librarySortOption"), SortOption.alphabetical.rawValue)
        XCTAssertEqual(defaults.string(forKey: "autofillAlgorithm"), "recentlyAdded")
        let reloaded = LibraryPreferences(defaults: defaults)
        XCTAssertEqual(reloaded.sortOption, .alphabetical)
        XCTAssertEqual(reloaded.autofillAlgorithm, .recentlyAdded)
    }
}
