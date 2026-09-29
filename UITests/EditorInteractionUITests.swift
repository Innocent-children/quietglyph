import XCTest
import AppKit

final class EditorInteractionUITests: XCTestCase {
    func testPastingWrappedTextAndUndo() {
        let pasteboard = NSPasteboard.general
        let savedItems = (pasteboard.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        }
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        defer {
            app.terminate()
            pasteboard.clearContents()
            pasteboard.writeObjects(savedItems)
        }
        let editor = app.textViews["editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        let area = app.scrollViews.containing(.textView, identifier: "editor").firstMatch
        area.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.25)).click()
        let text = String(repeating: "short line\n", count: 1000) + String(repeating: "long wrapped text ", count: 1000) + "\n" + String(repeating: "short\n", count: 5)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        app.typeKey("v", modifierFlags: .command)
        XCTAssertEqual(editor.value as? String, text)
        app.activate()
        let screenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        screenshot.name = "Pasted wrapped line and visible following lines"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.typeKey("z", modifierFlags: .command)
        XCTAssertEqual(editor.value as? String, "")
        app.typeKey("z", modifierFlags: [.command, .shift])
        XCTAssertEqual(editor.value as? String, text)
    }

    func testTypingAndUndo() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        let editor = app.textViews["editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        let area = app.scrollViews.containing(.textView, identifier: "editor").firstMatch
        area.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.25)).click()
        app.typeText("first\nsecond")
        XCTAssertEqual(editor.value as? String, "first\nsecond")
        app.typeKey("a", modifierFlags: .command)
        app.typeText("replacement")
        XCTAssertEqual(editor.value as? String, "replacement")
        app.typeKey("z", modifierFlags: .command)
        XCTAssertEqual(editor.value as? String, "first\nsecond")
        app.terminate()
    }
}
