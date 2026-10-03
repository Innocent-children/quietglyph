import XCTest
import AppKit
@testable import Inkline

final class BatchFileToolsTests: XCTestCase {
    @MainActor func testRenamePreviewConflictAndOpenDocumentMove() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("one.txt")
        try Data("original".utf8).write(to: url)
        var options = BatchRenameOptions(); options.prefix = "new-"
        let items = try BatchRenameService.preview(root: root, options: options)
        XCTAssertEqual(items.count, 1); XCTAssertEqual(items[0].destination.lastPathComponent, "new-one.txt")
        let document = TextDocument(); try document.read(from: url, ofType: "public.plain-text"); document.fileURL = url; document.fileType = "public.plain-text"
        let editor = EditorController(document: document); document.editor = editor; _ = editor.view
        defer { document.close() }
        editor.setSelections([NSRange(location: 0, length: 0)])
        editor.replaceSelections(with: "unsaved ", name: "Typing")
        try await BatchRenameService.execute(items[0], documents: [document])
        XCTAssertEqual(document.fileURL, items[0].destination); XCTAssertEqual(editor.textView.string, "unsaved original")
        XCTAssertEqual(try String(contentsOf: items[0].destination, encoding: .utf8), "original")
        try Data().write(to: root.appendingPathComponent("new-new-one.txt"))
        XCTAssertTrue(try BatchRenameService.preview(root: root, options: options).contains { $0.source.lastPathComponent == "new-one.txt" && $0.error != nil })
    }
    func testConversionPreservesLineEndingsAndRejectsStaleFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("one.txt"); try Data("中文\r\n".utf8).write(to: url)
        let item = try XCTUnwrap(BatchEncodingService.scan(root: root, patterns: "*.txt", recursive: false, openURLs: []).first)
        let data = try BatchEncodingService.prepare(item, encoding: .utf16LE, bom: true)
        let result = try TextFileCodec.decode(data)
        XCTAssertEqual(result.text, "中文\r\n"); XCTAssertTrue(result.metadata.hasBOM)
        try Data("changed".utf8).write(to: url)
        XCTAssertThrowsError(try BatchEncodingService.prepare(item, encoding: .gbk, bom: false))
    }
    func testExistingHardLinkTargetIsAPreviewConflict() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("one.txt"), target = root.appendingPathComponent("new-one.txt")
        try Data("original".utf8).write(to: source); try FileManager.default.linkItem(at: source, to: target)
        var options = BatchRenameOptions(); options.prefix = "new-"; options.patterns = "one.txt"
        let item = try XCTUnwrap(BatchRenameService.preview(root: root, options: options).first)
        XCTAssertNotNil(item.error)
    }
}
