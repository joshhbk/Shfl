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

    private func makeDeterministicApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--deterministic"]
        app.launch()
        return app
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
