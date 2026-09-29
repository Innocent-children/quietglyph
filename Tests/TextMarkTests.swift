import XCTest
import AppKit
@testable import QuietGlyph

final class TextMarkTests: XCTestCase {
    @MainActor func testMarksAndBookmarksRestoreAcrossDeletionUndoRedo() throws {
        let document = NativeTextDocument(); document.initialText = "first\nsecond\nthird"
        let editor = EditorController(document: document); document.editor = editor; _ = editor.view
        defer { document.close() }
        editor.mark([NSRange(location: 6, length: 6)], color: "Yellow"); editor.bookmarks.add([6])
        let undo = try XCTUnwrap(document.undoManager); undo.groupsByEvent = false
        undo.beginUndoGrouping(); try editor.apply([TextEdit(range: NSRange(location: 0, length: 13), replacement: "")], name: "Delete"); undo.endUndoGrouping()
        XCTAssertTrue(editor.marks.marks.isEmpty)
        undo.undo()
        XCTAssertEqual(editor.marks.marks.map(\.range), [NSRange(location: 6, length: 6)]); XCTAssertEqual(editor.bookmarks.offsets, [6])
        undo.redo(); XCTAssertTrue(editor.marks.marks.isEmpty)
    }
}
