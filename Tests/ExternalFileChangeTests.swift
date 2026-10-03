import AppKit
import XCTest
@testable import Inkline

final class ExternalFileChangeTests: XCTestCase {
    @MainActor private func openDocument(_ file: URL) throws -> TextDocument {
        let document = TextDocument()
        try document.read(from: file, ofType: "public.plain-text")
        document.fileURL = file
        document.fileType = "public.plain-text"
        document.makeWindowControllers()
        return document
    }

    private func fixture() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("document.txt")
        try Data("original".utf8).write(to: file)
        return file
    }

    @MainActor private func waitFor(_ state: TextDocument.ExternalFileState, in document: TextDocument) async throws {
        for _ in 0..<30 {
            if document.externalFileState == state { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertEqual(document.externalFileState, state)
    }

    @MainActor private func edit(_ document: TextDocument) throws {
        let editor = try XCTUnwrap(document.editor)
        let undo = try XCTUnwrap(document.undoManager)
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        editor.setSelections([NSRange(location: 0, length: editor.source.length)])
        editor.replaceSelections(with: "my unsaved edits", name: "Replace")
        undo.endUndoGrouping()
        XCTAssertTrue(document.isDocumentEdited)
    }

    @MainActor private func save(_ document: TextDocument, to url: URL, as operation: NSDocument.SaveOperationType) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            document.save(to: url, ofType: "public.plain-text", for: operation) { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }

    @MainActor func testHiddenDocumentDetectsRepeatedReplacementInPlaceWritesDeletionAndRecreation() async throws {
        let file = try fixture()
        let document = try openDocument(file)
        defer { document.close() }
        XCTAssertFalse(document.windowControllers.first?.window?.isVisible == true)
        for text in ["external one", "external two"] {
            try Data(text.utf8).write(to: file, options: .atomic)
            try await waitFor(.changed, in: document)
            XCTAssertNotEqual(document.editor?.textView.string, text)
            XCTAssertFalse(document.isDocumentEdited)
            try document.revert(toContentsOf: file, ofType: "public.plain-text")
            XCTAssertEqual(document.externalFileState, .unchanged)
            XCTAssertEqual(document.editor?.textView.string, text)
        }
        let handle = try FileHandle(forWritingTo: file)
        try handle.write(contentsOf: Data("in-place update".utf8))
        try handle.close()
        try await waitFor(.changed, in: document)
        try FileManager.default.removeItem(at: file)
        try await waitFor(.unavailable, in: document)
        XCTAssertEqual(document.editor?.textView.string, "external two")
        try Data("recreated".utf8).write(to: file)
        try await waitFor(.changed, in: document)
        try document.revert(toContentsOf: file, ofType: "public.plain-text")
        XCTAssertEqual(document.editor?.textView.string, "recreated")
        XCTAssertEqual(document.externalFileState, .unchanged)
    }

    @MainActor func testDirtyConflictPreservesEditsUndoAndDiskUntilExplicitReload() throws {
        let file = try fixture()
        let document = try openDocument(file)
        defer { document.close() }
        try edit(document)
        try Data("disk version".utf8).write(to: file, options: .atomic)
        document.checkForExternalChanges()
        XCTAssertEqual(document.externalFileState, .changed)
        XCTAssertEqual(document.editor?.textView.string, "my unsaved edits")
        XCTAssertTrue(document.undoManager?.canUndo == true)
        let revision = document.revision
        XCTAssertThrowsError(try document.writeSafely(to: file, ofType: "public.plain-text", for: .saveOperation))
        XCTAssertThrowsError(try document.writeSafely(to: file, ofType: "public.plain-text", for: .saveAsOperation))
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "disk version")
        try document.revert(toContentsOf: file, ofType: "public.plain-text")
        XCTAssertEqual(document.editor?.textView.string, "disk version")
        XCTAssertFalse(document.isDocumentEdited)
        XCTAssertFalse(document.undoManager?.canUndo == true)
        XCTAssertGreaterThan(document.revision, revision)
        XCTAssertEqual(document.externalFileState, .unchanged)
    }

    @MainActor func testSaveAsPreservesBothVersionsAndWatchesNewLocation() async throws {
        let file = try fixture()
        let copy = file.deletingLastPathComponent().appendingPathComponent("copy.txt")
        let document = try openDocument(file)
        defer { document.close() }
        try edit(document)
        try Data("external".utf8).write(to: file, options: .atomic)
        document.checkForExternalChanges()
        try await save(document, to: copy, as: .saveAsOperation)
        document.checkForExternalChanges()
        XCTAssertEqual(document.fileURL, copy)
        XCTAssertEqual(document.externalFileState, .unchanged)
        XCTAssertFalse(document.isDocumentEdited)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "external")
        XCTAssertEqual(try String(contentsOf: copy, encoding: .utf8), "my unsaved edits")
        try Data("another original update".utf8).write(to: file, options: .atomic)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(document.externalFileState, .unchanged)
        try Data("copy updated externally".utf8).write(to: copy, options: .atomic)
        try await waitFor(.changed, in: document)
    }

    @MainActor func testOwnSaveDoesNotReportConflictAndNextExternalWriteDoes() async throws {
        let file = try fixture()
        let document = try openDocument(file)
        defer { document.close() }
        try edit(document)
        try await save(document, to: file, as: .saveOperation)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(document.externalFileState, .unchanged)
        XCTAssertFalse(document.isDocumentEdited)
        try Data("external after save".utf8).write(to: file, options: .atomic)
        try await waitFor(.changed, in: document)
    }

    @MainActor func testMissingFileAndFailedReloadPreserveUnsavedContent() throws {
        let file = try fixture()
        let document = try openDocument(file)
        defer { document.close() }
        try edit(document)
        let editor = document.editor
        try FileManager.default.removeItem(at: file)
        document.checkForExternalChanges()
        XCTAssertEqual(document.externalFileState, .unavailable)
        XCTAssertThrowsError(try document.revert(toContentsOf: file, ofType: "public.plain-text"))
        XCTAssertThrowsError(try document.writeSafely(to: file, ofType: "public.plain-text", for: .saveOperation))
        XCTAssertTrue(document.editor === editor)
        XCTAssertEqual(document.editor?.textView.string, "my unsaved edits")
        XCTAssertTrue(document.isDocumentEdited)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    @MainActor func testConflictAfterAnExternalMoveCannotBypassSaveGuard() throws {
        let file = try fixture()
        let moved = file.deletingLastPathComponent().appendingPathComponent("moved.txt")
        let document = try openDocument(file)
        defer { document.close() }
        try edit(document)
        try FileManager.default.moveItem(at: file, to: moved)
        // Model AppKit updating the presented URL before its queued monitor refresh runs.
        document.fileURL = moved
        try Data("external at new path".utf8).write(to: moved, options: .atomic)
        XCTAssertThrowsError(try document.writeSafely(to: moved, ofType: "public.plain-text", for: .saveOperation))
        XCTAssertThrowsError(try document.writeSafely(to: moved, ofType: "public.plain-text", for: .saveAsOperation))
        XCTAssertEqual(try String(contentsOf: moved, encoding: .utf8), "external at new path")
        XCTAssertEqual(document.editor?.textView.string, "my unsaved edits")
    }

    @MainActor func testTimedSaveRefusesExternalConflict() async throws {
        let file = try fixture()
        let document = try openDocument(file)
        defer { document.close() }
        try edit(document)
        try Data("external before timed save".utf8).write(to: file, options: .atomic)
        let error = await document.saveTimed()
        XCTAssertNotNil(error)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "external before timed save")
        XCTAssertEqual(document.editor?.textView.string, "my unsaved edits")
        XCTAssertTrue(document.isDocumentEdited)
    }
}
