import XCTest

final class ExternalFileChangeUITests: XCTestCase {
    func testExternalChangeReloadConfirmationAndSaveAs() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("external-change.txt")
        try Data("original document".utf8).write(to: file)
        let suite = "inkline.external-change.ui.\(UUID().uuidString)"
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launchEnvironment["INKLINE_TEST_DEFAULTS"] = suite
        continueAfterFailure = false
        addTeardownBlock {
            app.terminate()
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: folder)
        }
        app.launch()
        XCTAssertTrue(app.textViews["editor"].waitForExistence(timeout: 10))
        app.typeKey("o", modifierFlags: .command)
        app.typeKey("g", modifierFlags: [.command, .shift])
        app.typeText(file.path)
        app.typeKey(.return, modifierFlags: [])
        app.typeKey(.return, modifierFlags: [])
        let window = app.windows["external-change.txt"]
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        let editor = window.textViews["editor"]
        XCTAssertEqual(editor.value as? String, "original document")
        let reload = window.buttons["reloadExternalChange"]
        try Data("first external version".utf8).write(to: file, options: .atomic)
        XCTAssertTrue(reload.waitForExistence(timeout: 5))
        XCTAssertEqual(editor.value as? String, "original document")
        capture(window, name: "Clean document changed on disk")
        reload.click()
        expectValue("first external version", in: editor)
        XCTAssertFalse(reload.exists)

        window.scrollViews.containing(.textView, identifier: "editor").firstMatch
            .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)).click()
        app.typeKey("a", modifierFlags: .command)
        app.typeText("my unsaved edits")
        try Data("second external version".utf8).write(to: file, options: .atomic)
        XCTAssertTrue(reload.waitForExistence(timeout: 5))
        XCTAssertEqual(editor.value as? String, "my unsaved edits")
        reload.click()
        let keep = app.buttons["keepExternalEdits"]
        XCTAssertTrue(keep.waitForExistence(timeout: 3))
        capture(window, name: "Dirty document reload confirmation")
        keep.click()
        XCTAssertEqual(editor.value as? String, "my unsaved edits")
        XCTAssertTrue(reload.exists)
        window.buttons["saveExternalChangeAs"].click()
        let savePanel = window.sheets.firstMatch
        XCTAssertTrue(savePanel.waitForExistence(timeout: 3))
        app.typeKey("g", modifierFlags: [.command, .shift])
        app.typeText(folder.path)
        app.typeKey(.return, modifierFlags: [])
        let name = savePanel.textFields["saveAsNameTextField"]
        name.click(); app.typeKey("a", modifierFlags: .command); app.typeText("preserved-edits.txt")
        savePanel.buttons["OKButton"].click()
        let savedWindow = app.windows["preserved-edits.txt"]
        XCTAssertTrue(savedWindow.waitForExistence(timeout: 5))
        XCTAssertFalse(savedWindow.buttons["reloadExternalChange"].exists)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "second external version")
        let copy = folder.appendingPathComponent("preserved-edits.txt")
        XCTAssertEqual(try String(contentsOf: copy, encoding: .utf8), "my unsaved edits")

        let savedEditor = savedWindow.textViews["editor"]
        savedWindow.scrollViews.containing(.textView, identifier: "editor").firstMatch
            .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)).click()
        app.typeKey("a", modifierFlags: .command); app.typeText("edits to discard")
        try Data("latest copy on disk".utf8).write(to: copy, options: .atomic)
        let copyReload = savedWindow.buttons["reloadExternalChange"]
        XCTAssertTrue(copyReload.waitForExistence(timeout: 5))
        copyReload.click()
        app.buttons["confirmExternalReload"].click()
        expectValue("latest copy on disk", in: savedEditor)
        XCTAssertFalse(copyReload.exists)
    }

    private func expectValue(_ value: String, in element: XCUIElement) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed)
    }

    private func capture(_ window: XCUIElement, name: String) {
        let attachment = XCTAttachment(screenshot: window.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
