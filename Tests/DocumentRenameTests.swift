import AppKit
import XCTest
@testable import QuietGlyph

final class DocumentRenameTests: XCTestCase {
    @MainActor private func rename(_ document: NativeTextDocument, to name: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            document.rename(to: name) { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }

    @MainActor func testUntitledRenameUpdatesTitleAndSuggestedSaveName() async throws {
        let document = NativeTextDocument()
        document.makeWindowControllers()
        defer { document.close() }
        try await rename(document, to: "新的笔记.txt")
        XCTAssertNil(document.fileURL)
        XCTAssertEqual(document.displayName, "新的笔记.txt")
        XCTAssertEqual(document.windowControllers.first?.window?.title, "新的笔记.txt")
        let panel = NSSavePanel()
        XCTAssertTrue(document.prepareSavePanel(panel))
        XCTAssertEqual(panel.nameFieldStringValue, "新的笔记.txt")
    }

    @MainActor func testRenameRejectsInvalidNamesAndExistingFiles() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let original = folder.appendingPathComponent("original.txt")
        let existing = folder.appendingPathComponent("existing.txt")
        try Data("original".utf8).write(to: original)
        try Data("existing".utf8).write(to: existing)
        let document = NativeTextDocument()
        try document.read(from: original, ofType: "public.plain-text")
        document.fileURL = original
        document.fileType = "public.plain-text"
        defer { document.close() }
        for invalidName in ["", "   ", ".", "..", "../escape.txt", "bad:name", "bad\0name", "existing.txt"] {
            do {
                try await rename(document, to: invalidName)
                XCTFail("Expected failure for \(invalidName)")
            } catch {
                XCTAssertEqual(document.fileURL, original)
                XCTAssertEqual(try String(contentsOf: original, encoding: .utf8), "original")
                XCTAssertEqual(try String(contentsOf: existing, encoding: .utf8), "existing")
            }
        }
        try await rename(document, to: "original.txt")
        XCTAssertEqual(document.fileURL, original)
    }

    @MainActor private func move(_ document: NativeTextDocument, to url: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            document.move(to: url) { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }

    @MainActor func testRenamePreservesUnsavedEditsAndSavesToNewPath() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let original = folder.appendingPathComponent("original.txt")
        let renamed = folder.appendingPathComponent("改名后.txt")
        try Data("disk content".utf8).write(to: original)
        let document = NativeTextDocument()
        try document.read(from: original, ofType: "public.plain-text")
        document.fileURL = original
        document.fileType = "public.plain-text"
        document.makeWindowControllers()
        defer { document.close() }
        let editor = try XCTUnwrap(document.editor)
        let undo = try XCTUnwrap(document.undoManager)
        undo.groupsByEvent = false
        editor.setSelections([NSRange(location: 0, length: editor.source.length)])
        undo.beginUndoGrouping()
        editor.paste("unsaved edits")
        undo.endUndoGrouping()
        XCTAssertTrue(document.isDocumentEdited)

        try await rename(document, to: renamed.lastPathComponent)

        XCTAssertEqual(document.fileURL, renamed)
        XCTAssertEqual(document.displayName, renamed.lastPathComponent)
        XCTAssertFalse(FileManager.default.fileExists(atPath: original.path))
        XCTAssertEqual(try String(contentsOf: renamed, encoding: .utf8), "disk content")
        XCTAssertEqual(editor.textView.string, "unsaved edits")
        XCTAssertTrue(document.isDocumentEdited)
        try document.writeSafely(to: renamed, ofType: "public.plain-text", for: .saveOperation)
        XCTAssertEqual(try String(contentsOf: renamed, encoding: .utf8), "unsaved edits")

        try Data("external change after rename".utf8).write(to: renamed, options: .atomic)
        XCTAssertThrowsError(try document.writeSafely(to: renamed, ofType: "public.plain-text", for: .saveOperation))
        XCTAssertEqual(try String(contentsOf: renamed, encoding: .utf8), "external change after rename")
    }

    @MainActor func testFailedRenameKeepsOriginalPathAndContents() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let original = folder.appendingPathComponent("original.txt")
        try Data("original".utf8).write(to: original)
        let document = NativeTextDocument()
        try document.read(from: original, ofType: "public.plain-text")
        document.fileURL = original
        document.fileType = "public.plain-text"
        defer { document.close() }
        do {
            try await move(document, to: folder.appendingPathComponent("missing/new.txt"))
            XCTFail("Moving into a missing directory should fail")
        } catch {
            XCTAssertEqual(document.fileURL, original)
            XCTAssertEqual(try String(contentsOf: original, encoding: .utf8), "original")
        }
    }
}
