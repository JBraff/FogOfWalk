import XCTest

final class BackupImportInteractionTests: XCTestCase {
    @MainActor
    func testInlineChoicesRequireConfirmationAndSupportCancelAndMerge() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-backup-import-fixture"]
        app.launch()
        let load = app.buttons["Load Fictional Backup"]
        XCTAssertTrue(load.waitForExistence(timeout: 10))
        let result = app.staticTexts["import-result"]
        load.tap()
        XCTAssertTrue(app.buttons["Replace…"].waitForExistence(timeout: 3))
        XCTAssertEqual(result.label, "No import")
        app.buttons["Replace…"].tap()
        let confirmation = app.alerts["Replace Existing Data?"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 3))
        XCTAssertEqual(result.label, "No import", "Choosing Replace must not import before confirmation")
        confirmation.buttons["Cancel"].tap()
        XCTAssertEqual(result.label, "No import")
        XCTAssertTrue(app.buttons["Replace…"].exists)
        app.buttons["Replace…"].tap()
        XCTAssertTrue(confirmation.waitForExistence(timeout: 3))
        confirmation.buttons["Replace"].tap()
        XCTAssertEqual(result.label, "Replaced")
        XCTAssertFalse(app.buttons["Replace…"].exists)

        load.tap()
        app.buttons["Cancel Import"].tap()
        XCTAssertEqual(result.label, "Cancelled")
        XCTAssertFalse(app.buttons["Replace…"].exists)
        load.tap()
        app.buttons["Merge"].tap()
        XCTAssertEqual(result.label, "Merged")
        XCTAssertFalse(confirmation.exists)
    }
}
