import XCTest
import AppKit
@testable import Inkline

final class AutosaveTests: XCTestCase {
    @MainActor func testOptionalThreeMinuteSaveAndCompositionSkip() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("old".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let document = TextDocument(); try document.read(from: url, ofType: "public.plain-text")
        document.fileURL = url; document.fileType = "public.plain-text"
        let editor = EditorController(document: document); document.editor = editor; _ = editor.view
        defer { document.close() }
        editor.setSelections([NSRange(location: 0, length: 3)])
        document.undoManager?.groupsByEvent = false
        document.undoManager?.beginUndoGrouping(); editor.replaceSelections(with: "new", name: "Replace"); document.undoManager?.endUndoGrouping()
        let controller = AutosaveController(documents: { [document] }, now: { 0 })
        var errors: [Error] = []; controller.onError = { _, error in errors.append(error) }
        await controller.tick(at: 180)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "old")
        controller.configure(enabled: true, scheduleTimer: false)
        await controller.tick(at: 179); XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "old")
        await controller.tick(at: 180); XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "new")
        XCTAssertTrue(errors.isEmpty); XCTAssertFalse(document.isDocumentEdited)
        editor.textView.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        await controller.tick(at: 360); XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "new")
        editor.textView.cancelOperation(nil)
        controller.stop(); XCTAssertFalse(controller.enabled)
    }
}
