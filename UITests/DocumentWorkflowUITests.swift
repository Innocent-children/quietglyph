import XCTest

final class DocumentWorkflowUITests: XCTestCase {
    func testNewDocumentFindAndReplace() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        let editor = app.textViews["editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        let area = app.scrollViews.containing(.textView, identifier: "editor").firstMatch
        area.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.25)).click()
        app.typeText("alpha beta alpha")
        app.typeKey("f", modifierFlags: .command)
        let find = app.textFields["findField"]
        XCTAssertTrue(find.waitForExistence(timeout: 3))
        find.click(); find.typeText("alpha")
        let replacement = app.textFields["replaceField"]
        replacement.click(); replacement.typeText("gamma")
        let replaceAll = app.buttons.matching(NSPredicate(format: "label == 'Replace All' OR label == '全部替换'")).firstMatch
        replaceAll.click()
        XCTAssertEqual(editor.value as? String, "gamma beta gamma")
        app.terminate()
    }
}
