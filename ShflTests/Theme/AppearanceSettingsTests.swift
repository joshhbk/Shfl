import XCTest
@testable import Shfl

@MainActor
final class AppearanceSettingsTests: XCTestCase {
    private let suiteName = "AppearanceSettingsTests"

    override func tearDown() {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testFirstLaunchPicksOneOfTheThemes() throws {
        let settings = AppearanceSettings(defaults: try XCTUnwrap(UserDefaults(suiteName: suiteName)))

        XCTAssertTrue(ShuffleTheme.allThemes.map(\.id).contains(settings.currentThemeId))
    }

    func testThemeIsSavedUnderTheExistingKey() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let settings = AppearanceSettings(defaults: defaults)

        settings.currentThemeId = "silver"

        XCTAssertEqual(defaults.string(forKey: "currentThemeId"), "silver")
        XCTAssertEqual(AppearanceSettings(defaults: defaults).currentThemeId, "silver")
    }
}
