import XCTest

final class EditingAndToolsUITests: XCTestCase {
    func testMultilineTabSearchReplacementAndToolPanels() {
        let app = XCUIApplication()
        let suite = "inkline.editing-tools.ui.\(UUID().uuidString)"
        app.launchArguments = ["--ui-testing"]
        app.launchEnvironment["INKLINE_TEST_DEFAULTS"] = suite
        app.launch()
        defer { app.terminate(); UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let editor = app.textViews["editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        let area = app.scrollViews.containing(.textView, identifier: "editor").firstMatch
        area.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)).click()
        app.typeText("one\ntwo")
        app.typeKey("a", modifierFlags: .command); app.typeKey(.tab, modifierFlags: [])
        XCTAssertEqual(editor.value as? String, "    one\n    two")
        app.typeKey("z", modifierFlags: .command)
        XCTAssertEqual(editor.value as? String, "one\ntwo")
        app.typeKey("f", modifierFlags: .command)
        let find = app.textFields["findField"], replace = app.textFields["replaceField"]
        XCTAssertTrue(find.waitForExistence(timeout: 5))
        find.click(); find.typeText("one"); replace.click(); replace.typeText("ONE")
        app.buttons["全部替换"].click()
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "ONE\ntwo"), object: editor)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
        area.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).click()
        app.typeKey("z", modifierFlags: .command)
        XCTAssertEqual(editor.value as? String, "one\ntwo")
        app.menuBars.menuBarItems["文件"].click(); app.menuItems["batch-rename"].click()
        let rename = app.windows["批量重命名"]
        XCTAssertTrue(rename.waitForExistence(timeout: 5)); XCTAssertTrue(rename.buttons["预览"].exists)
        rename.buttons[XCUIIdentifierCloseWindow].click()
        app.menuBars.menuBarItems["搜索"].click(); app.menuItems["batch-find"].click()
        let batch = app.windows["批量查找与替换"]
        XCTAssertTrue(batch.waitForExistence(timeout: 5)); XCTAssertTrue(batch.buttons["添加规则"].exists)
        let capture = XCTAttachment(screenshot: batch.screenshot()); capture.name = "Batch rules"; capture.lifetime = .keepAlways; add(capture)
    }
}
