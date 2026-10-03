import XCTest
import AppKit
@testable import Inkline

final class EditorTransactionTests: XCTestCase {
    @MainActor func testMultilineTabAndUndoPreserveContentAndSelections() throws {
        let document = TextDocument(); document.initialText = "alpha\r\nbeta"
        let editor = EditorController(document: document); document.editor = editor; _ = editor.view
        let settings = SettingsStore.shared.values
        defer { SettingsStore.shared.values = settings; document.close() }
        SettingsStore.shared.values.useSpaces = true
        SettingsStore.shared.values.tabWidth = 4
        let selection = NSRange(location: 0, length: 11)
        editor.setSelections([selection])
        let undo = try XCTUnwrap(document.undoManager); undo.groupsByEvent = false
        undo.beginUndoGrouping(); editor.textView.insertTab(nil); undo.endUndoGrouping()
        XCTAssertEqual(editor.textView.string, "    alpha\r\n    beta")
        undo.undo()
        XCTAssertEqual(editor.textView.string, "alpha\r\nbeta")
        XCTAssertEqual(editor.selections.ranges, [selection])
        undo.redo()
        XCTAssertEqual(editor.textView.string, "    alpha\r\n    beta")
    }
    @MainActor func testMultiCaretKeyboardThenTypingAndWholeDocumentSort() throws {
        let document = TextDocument(); document.initialText = "abc\nabc"
        let editor = EditorController(document: document); document.editor = editor; _ = editor.view
        defer { document.close() }
        editor.setSelections([NSRange(location: 1, length: 0), NSRange(location: 5, length: 0)])
        editor.textView.doCommand(by: NSSelectorFromString("moveRight:"))
        XCTAssertEqual(editor.selections.ranges.map(\.location), [2, 6])
        editor.textView.doCommand(by: NSSelectorFromString("moveLeftAndModifySelection:"))
        editor.replaceSelections(with: "!", name: "Replace")
        XCTAssertEqual(editor.textView.string, "a!c\na!c")
        editor.transform(name: "Replace") { _ in "z\na\nm" }
        editor.setSelections([NSRange(location: 2, length: 0)])
        editor.run(LineCommand.sortAscending)
        XCTAssertEqual(editor.textView.string, "a\nm\nz")
    }
    @MainActor func testSavingSeparatesTypingUndoGroups() throws {
        let document = TextDocument(); document.initialText = "original"
        let editor = EditorController(document: document); document.editor = editor; _ = editor.view
        let undo = try XCTUnwrap(document.undoManager)
        undo.groupsByEvent = false
        func typeEvent(_ text: String) {
            undo.beginUndoGrouping()
            editor.textView.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
            undo.endUndoGrouping()
        }
        editor.setSelections([NSRange(location: 8, length: 0)])
        typeEvent("a")
        _ = try document.data(ofType: "public.plain-text")
        document.updateChangeCount(.changeCleared)
        typeEvent("b")
        XCTAssertTrue(document.isDocumentEdited)
        document.undoManager?.undo()
        XCTAssertEqual(editor.textView.string, "originala")
        XCTAssertFalse(document.isDocumentEdited)
        document.close()
    }
    func testMultipleReplacementsAndInverseRestoreUnicode() throws {
        let original = "猫🙂 dog\n猫🙂 dog"
        let source = original as NSString
        let first = source.range(of: "dog")
        let second = source.range(of: "dog", options: .backwards)
        let result = try EditTransaction.applying([TextEdit(range: first, replacement: "狐狸"), TextEdit(range: second, replacement: "")], to: original)
        XCTAssertEqual(result.text, "猫🙂 狐狸\n猫🙂 ")
        XCTAssertEqual(try EditTransaction.applying(result.inverse, to: result.text).text, original)
    }
    func testOverlappingEditsAndSplitSurrogateAreRejected() {
        XCTAssertThrowsError(try EditTransaction.applying([TextEdit(range: NSRange(location: 1, length: 1), replacement: "")], to: "🙂"))
        XCTAssertThrowsError(try EditTransaction.applying([TextEdit(range: NSRange(location: 0, length: 2), replacement: ""), TextEdit(range: NSRange(location: 1, length: 1), replacement: "")], to: "abc"))
    }
    @MainActor func testMultiCaretUndoAndMarkedTextCommit() throws {
        let document = TextDocument()
        document.initialText = "a\na"
        let editor = EditorController(document: document)
        document.editor = editor
        _ = editor.view
        document.undoManager?.groupsByEvent = false
        editor.setSelections([NSRange(location: 1, length: 0), NSRange(location: 3, length: 0)])
        document.undoManager?.beginUndoGrouping()
        editor.textView.insertText("🙂", replacementRange: NSRange(location: NSNotFound, length: 0))
        document.undoManager?.endUndoGrouping()
        XCTAssertEqual(editor.textView.string, "a🙂\na🙂")
        document.undoManager?.undo()
        XCTAssertEqual(editor.textView.string, "a\na")
        XCTAssertFalse(document.isDocumentEdited)
        editor.setSelections([NSRange(location: 1, length: 0), NSRange(location: 3, length: 0)])
        document.undoManager?.beginUndoGrouping()
        editor.textView.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        editor.textView.insertText("你", replacementRange: NSRange(location: NSNotFound, length: 0))
        document.undoManager?.endUndoGrouping()
        XCTAssertEqual(editor.textView.string, "a你\na你")
        document.undoManager?.undo()
        XCTAssertEqual(editor.textView.string, "a\na")
        XCTAssertFalse(document.isDocumentEdited)
        editor.textView.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertTrue(document.isDocumentEdited)
        editor.textView.cancelOperation(nil)
        XCTAssertEqual(editor.textView.string, "a\na")
        XCTAssertFalse(document.isDocumentEdited)
        document.close()
    }
}
