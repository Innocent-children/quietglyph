import XCTest

final class AccessibilityUITests: XCTestCase {
    func testEditorAndSidebarNavigationAreExposed() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(app.textViews["editor"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.dialogs.firstMatch.exists, "A clean test launch must not show a file-open error.")
        XCTAssertTrue(app.toolbars.firstMatch.exists)
        XCTAssertTrue(app.menuBars.firstMatch.exists)
        XCTAssertGreaterThan(app.buttons.count, 0)
        app.terminate()
    }
}
