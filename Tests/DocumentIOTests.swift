import XCTest
@testable import QuietGlyph

final class DocumentIOTests: XCTestCase {
    @MainActor func testSidebarTracksSavedStateAndFileName() throws {
        let controller = DocumentController()
        let document = TextDocument()
        controller.addDocument(document)
        document.makeWindowControllers()
        defer { controller.removeDocument(document); document.close() }
        let window = try XCTUnwrap(document.windowControllers.first as? DocumentWindowController)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("sidebar-save-check.txt")
        document.updateChangeCount(.changeDone)
        XCTAssertEqual(window.sidebarModel.documents.first(where: { $0.id == document.recoveryID })?.modified, true)
        document.fileURL = file
        document.updateChangeCount(.changeCleared)
        let saved = try XCTUnwrap(window.sidebarModel.documents.first(where: { $0.id == document.recoveryID }))
        XCTAssertEqual(saved.title, file.lastPathComponent)
        XCTAssertFalse(saved.modified)
    }

    @MainActor func testRevertUpdatesTheLiveEditorAndClearsChanges() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("txt")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("old content".utf8).write(to: file)
        let document = TextDocument()
        try document.read(from: file, ofType: "public.plain-text")
        document.fileURL = file
        document.fileType = "public.plain-text"
        document.makeWindowControllers()
        XCTAssertEqual(document.editor?.textView.string, "old content")
        try Data("new disk content 中文".utf8).write(to: file, options: .atomic)
        try document.revert(toContentsOf: file, ofType: "public.plain-text")
        XCTAssertEqual(document.editor?.textView.string, "new disk content 中文")
        XCTAssertFalse(document.isDocumentEdited)
        XCTAssertEqual(try String(data: document.data(ofType: "public.plain-text"), encoding: .utf8), "new disk content 中文")
        document.close()
    }
    @MainActor func testTextDocumentSafeWriteAndExternalChangeGuard() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("txt")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("original\r\n".utf8).write(to: file)
        let document = TextDocument()
        try document.read(from: file, ofType: "public.plain-text")
        document.fileURL = file
        document.initialText = "saved 中文🙂\r\n"
        try document.writeSafely(to: file, ofType: "public.plain-text", for: .saveOperation)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "saved 中文🙂\r\n")
        try Data("external change".utf8).write(to: file, options: .atomic)
        XCTAssertThrowsError(try document.writeSafely(to: file, ofType: "public.plain-text", for: .saveOperation))
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "external change")
        document.close()
    }
    func testStaleReplacementPreservesExternalChanges() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("sample.txt")
        try Data("old".utf8).write(to: file)
        let old = try DocumentIO.stamp(file)
        try Data("external version".utf8).write(to: file, options: .atomic)
        XCTAssertThrowsError(try DocumentIO.replace(file, data: Data("replacement".utf8), expected: old))
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "external version")
    }
    func testAtomicReplacementPreservesMode() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("old".utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: file.path)
        try DocumentIO.replace(file, data: Data("new".utf8), expected: DocumentIO.stamp(file))
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "new")
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)?.intValue, 0o640)
    }
}
