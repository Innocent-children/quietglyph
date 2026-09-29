import XCTest
@testable import QuietGlyph

final class SearchTests: XCTestCase {
    @MainActor func testSelectionNavigationDoesNotEscapeWithoutWrap() {
        let document = NativeTextDocument(); document.initialText = "cat cat cat"
        let editor = EditorController(document: document); document.editor = editor; _ = editor.view
        defer { document.close() }
        editor.setSelections([NSRange(location: 4, length: 3)])
        let model = SearchPanelModel(); model.editor = editor; model.scope = .selection; model.pattern = "cat"; model.wrap = false
        model.next(); XCTAssertEqual(editor.textView.selectedRange(), NSRange(location: 4, length: 3))
        model.next(); XCTAssertEqual(editor.textView.selectedRange(), NSRange(location: 4, length: 3))
        model.next(backwards: true); XCTAssertEqual(editor.textView.selectedRange(), NSRange(location: 4, length: 3))
    }
    @MainActor func testDirectorySearchUsesMemoryAndPreservesDiskUntilManualSave() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("open.txt"), closed = root.appendingPathComponent("closed.txt")
        try Data("disk".utf8).write(to: url); try Data("cat".utf8).write(to: closed)
        let document = NativeTextDocument(); document.initialText = "cat"; document.fileURL = url
        let editor = EditorController(document: document); document.editor = editor; _ = editor.view
        NSDocumentController.shared.addDocument(document)
        defer { document.close() }
        var query = SearchQuery(); query.text = "cat"; query.replacement = "dog"
        let snapshots = SearchCoordinator.snapshots(scope: .directory, editor: editor, root: root, query: query)
        let found = await SearchCoordinator.find(snapshots, root: root, query: query)
        XCTAssertEqual(found.results.count, 2)
        let result = await SearchCoordinator.replace(found.results, query: query, editor: editor)
        XCTAssertEqual(result.changedOpenDocuments, 1); XCTAssertEqual(result.changedClosedFiles, 1)
        XCTAssertEqual(editor.textView.string, "dog"); XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "disk")
        XCTAssertEqual(try String(contentsOf: closed, encoding: .utf8), "dog")
    }
    func testExtendedModeMatchesOriginalSupportedEscapes() throws {
        XCTAssertEqual(SearchService.expand(#"\b01000001\o102\d067\x44\u4e2d\r\n\t\0\\\q"#), "ABCD中\r\n\t\0\\\\q")
        XCTAssertEqual(SearchService.expand(#"\xQ1\u12"#), #"\xQ1\u12"#)
        var query = SearchQuery(); query.text = #"a\tb"#; query.replacement = #"\u732b\n"#; query.extended = true
        let edits = try SearchService.edits(query, in: "a\tb")
        XCTAssertEqual(try EditTransaction.applying(edits, to: "a\tb").text, "猫\n")
    }
    @MainActor func testOpenUnsavedSnapshotAndStaleReplacement() async throws {
        let document = NativeTextDocument(); document.initialText = "cat"
        let editor = EditorController(document: document); document.editor = editor; _ = editor.view
        NSDocumentController.shared.addDocument(document)
        defer { document.close() }
        var query = SearchQuery(); query.text = "cat"; query.replacement = "dog"
        let snapshots = SearchCoordinator.snapshots(scope: .openDocuments, editor: editor, root: nil, query: query)
        let found = await SearchCoordinator.find(snapshots, root: nil, query: query)
        XCTAssertEqual(found.results.filter { $0.documentID == document.recoveryID }.count, 1)
        let replaced = await SearchCoordinator.replace(found.results, query: query, editor: editor)
        XCTAssertEqual(replaced.changedOpenDocuments, 1)
        XCTAssertEqual(editor.textView.string, "dog"); XCTAssertNil(document.fileURL)
        let stale = await SearchCoordinator.replace(found.results, query: query, editor: editor)
        XCTAssertEqual(stale.changed, 0); XCTAssertFalse(stale.failures.isEmpty)
    }
    func testUnicodeWholeWordsAndRegexGroups() throws {
        var query = SearchQuery()
        query.text = "cat"; query.wholeWord = true
        XCTAssertEqual(try SearchService.matches(query, in: "Cat scatter cat").count, 2)
        query.text = "(猫)(🙂)"; query.regularExpression = true; query.wholeWord = false; query.replacement = "$2$1"
        let text = "猫🙂 猫🙂"
        let edits = try SearchService.edits(query, in: text)
        XCTAssertEqual(try EditTransaction.applying(edits, to: text).text, "🙂猫 🙂猫")
    }
    func testInvalidPatternAndEmptySearch() {
        var query = SearchQuery(); query.text = "("; query.regularExpression = true
        XCTAssertThrowsError(try SearchService.matches(query, in: "text"))
        query.text = ""
        XCTAssertEqual(try SearchService.matches(query, in: "text").count, 0)
    }
}
