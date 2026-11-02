import XCTest

final class RoutePreviewInteractionTests: XCTestCase {
    @MainActor
    func testOfflineComparisonSelectionSearchAndClear() {
        let app = XCUIApplication()
        app.launchArguments = ["-route-prototype-fixture"]
        app.launch()
        app.buttons["Compare routes"].tap()
        let first = app.buttons["route-option-0"]
        let second = app.buttons["route-option-1"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertTrue(second.exists)
        XCTAssertTrue(first.label.contains("new cells"))
        XCTAssertTrue(second.label.contains("new cells"))
        second.tap()
        XCTAssertEqual(second.value as? String, "Selected")
        XCTAssertEqual(first.value as? String, "Not selected")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Destination-first route comparison (offline demo)"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["Done"].tap()
        XCTAssertTrue(app.maps.firstMatch.exists)
        let mapScreenshot = XCTAttachment(screenshot: app.screenshot())
        mapScreenshot.name = "Selected route above fog (offline demo)"
        mapScreenshot.lifetime = .keepAlways
        add(mapScreenshot)
        app.buttons["Compare routes"].tap()
        let field = app.searchFields.firstMatch
        field.tap(); field.typeText("Park\n")
        let result = app.buttons["route-destination-0"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        result.tap()
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        app.buttons["Clear routes"].tap()
        XCTAssertFalse(first.exists)
        app.buttons["Done"].tap()
        XCTAssertFalse(app.buttons["Clear route preview"].exists)
    }
}
