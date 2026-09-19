import XCTest

final class ShflLaunchUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testPlaybackScenarioStartsPausesResumesAndAdvances() {
        let app = makeDeterministicApp()
        XCTAssertTrue(app.staticTexts["Ready to shuffle"].waitForExistence(timeout: 10))

        let playPause = element("player.playPause", in: app)
        XCTAssertTrue(playPause.waitForExistence(timeout: 2))
        playPause.tap()

        let songTitle = element("player.songTitle", in: app)
        assertLabel("Low Tide", for: songTitle)
        assertLabel("Pause", for: playPause)

        playPause.tap()
        assertLabel("Play", for: playPause)
        assertLabel("Low Tide", for: songTitle)

        playPause.tap()
        assertLabel("Pause", for: playPause)

        let skipForward = element("player.skipForward", in: app)
        XCTAssertTrue(skipForward.waitForExistence(timeout: 2))
        skipForward.tap()
        assertLabel("Second Wind", for: songTitle)
    }

    func testSongPickerAutofillStopsWhenLibraryIsExhausted() {
        let app = makeDeterministicApp()
        openSongPicker(in: app)

        element("songPicker.autofill", in: app).tap()

        XCTAssertTrue(element("songPicker.autofill", in: app).waitForNonExistence(timeout: 5))

        app.buttons["Afterglow, Paper Satellites"].tap()
        XCTAssertTrue(element("songPicker.autofill", in: app).waitForExistence(timeout: 5))
    }

    func testSongPickerSearchPrioritizesResultsOverAutofill() {
        let app = makeDeterministicApp()
        openSongPicker(in: app)

        let searchField = element("songPicker.search", in: app)
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        searchField.typeText("Low")

        XCTAssertTrue(app.buttons["Low Tide, Harbour Lights"].waitForExistence(timeout: 5))
        XCTAssertFalse(element("songPicker.autofill", in: app).exists)
    }

    func testSongPickerDetailKeepsCompletionAndHidesRootControls() {
        let app = makeDeterministicApp()
        openSongPicker(in: app)

        let scope = element("songPicker.scope", in: app)
        XCTAssertTrue(scope.waitForExistence(timeout: 5))
        scope.buttons["Artists"].tap()
        app.buttons["Paper Satellites"].tap()

        XCTAssertTrue(app.navigationBars["Paper Satellites"].waitForExistence(timeout: 5))
        XCTAssertTrue(element("songPicker.autofill", in: app).exists)
        XCTAssertFalse(element("songPicker.search", in: app).exists)
    }

    func testSongPickerClearImmediatelyRemovesSelection() {
        let app = makeDeterministicApp()
        openSongPicker(in: app)

        XCTAssertTrue(element("songPicker.close", in: app).exists)

        element("songPicker.clear", in: app).tap()
        XCTAssertFalse(element("songPicker.clear", in: app).exists)
        XCTAssertTrue(element("songPicker.autofill", in: app).exists)
    }

    private func makeDeterministicApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--deterministic"]
        app.launch()
        return app
    }

    private func openSongPicker(in app: XCUIApplication) {
        let pickerButton = app.buttons["Playlist"]
        XCTAssertTrue(pickerButton.waitForExistence(timeout: 10))
        pickerButton.tap()
        XCTAssertTrue(app.navigationBars["Pick Your Songs"].waitForExistence(timeout: 5))
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func assertLabel(
        _ expectedLabel: String,
        for element: XCUIElement,
        timeout: TimeInterval = 5
    ) {
        let predicate = NSPredicate(format: "label == %@", expectedLabel)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: timeout),
            .completed,
            "Expected \(element) to have label \(expectedLabel)."
        )
    }
}
