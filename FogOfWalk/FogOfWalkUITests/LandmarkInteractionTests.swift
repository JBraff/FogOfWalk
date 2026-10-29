import XCTest

/// Real finger gestures against the production map coordinator and annotation views.
final class LandmarkInteractionTests: XCTestCase {
    @MainActor
    func testPinTapRepeatDragHintDiscoveryZoomAndRotation() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-landmark-interaction-fixture"]
        app.launch()
        let pin = app.buttons["landmark-Q1"]
        XCTAssertTrue(pin.waitForExistence(timeout: 10))
        let status = app.staticTexts["fixture-status"]
        pin.tap()
        waitForTaps(1, status: status)
        pin.tap()
        waitForTaps(2, status: status)

        app.buttons["Read map"].tap()
        let before = status.label
        // Starting directly on a discovered pin must pan, without opening details.
        let start = pin.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 85, dy: 45)))
        app.buttons["Read map"].tap()
        XCTAssertNotEqual(status.label, before, "Dragging from a pin must move the camera")
        XCTAssertTrue(status.label.hasSuffix("Taps: 2"), "A drag must not select the pin")
        waitForGeometry(app)
        XCTAssertTrue(app.buttons["landmark-Q2"].isHittable, "Buffered pins must enter from the edge")

        app.buttons["Reset map"].tap()
        let map = app.maps.firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["Make hint"].tap()
        XCTAssertFalse(pin.exists, "A hint must not expose a discovered-pin button")
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(status.label.hasSuffix("Taps: 2"))
        app.buttons["Discover hint"].tap()
        XCTAssertTrue(pin.waitForExistence(timeout: 5))
        pin.tap()
        waitForTaps(3, status: status)

        map.pinch(withScale: 1.5, velocity: 1)
        app.buttons["Read map"].tap()
        waitForGeometry(app)
        map.rotate(.pi / 4, withVelocity: 1)
        app.buttons["Read map"].tap()
        waitForGeometry(app)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Native landmark above fog after zoom and rotation"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
    @MainActor
    private func waitForGeometry(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Aligned; fixed size"),
                                                    object: app.staticTexts["fixture-geometry"])
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 4), .completed, file: file, line: line)
    }

    @MainActor
    private func waitForTaps(_ count: Int, status: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        // MapKit defers selection past XCUITest's first idle check (double-tap arbitration).
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Taps: \(count)"),
                                                    object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 4), .completed, file: file, line: line)
    }

}
