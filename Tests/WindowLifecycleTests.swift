import AppKit
import XCTest
@testable import QuietGlyph

final class WindowLifecycleTests: XCTestCase {
    @MainActor func testCenteredTitleKeepsRenamePopoverCloseAndFollowsNameChanges() async throws {
        let document = TextDocument()
        document.makeWindowControllers()
        defer { document.close() }
        document.showWindows()
        let window = try XCTUnwrap(document.windowControllers.first?.window)
        try await Task.sleep(for: .milliseconds(100))
        window.contentView?.superview?.layoutSubtreeIfNeeded()
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let frame = try XCTUnwrap(window.contentView?.superview)
        let arrow = try XCTUnwrap(descendants(frame).compactMap { $0 as? NSButton }.first { $0.accessibilityIdentifier() == "documentRename" })
        let titleRect = arrow.convert(arrow.bounds, to: frame)
        XCTAssertEqual(titleRect.midX, frame.bounds.midX, accuracy: 1)
        XCTAssertEqual(arrow.title, document.displayName)
        XCTAssertTrue(frame.hitTest(arrow.convert(NSPoint(x: 9, y: 9), to: frame)) === arrow)
        let controller = try XCTUnwrap(document.windowControllers.first as? DocumentWindowController)
        controller.showDocumentRename(nil)
        try await Task.sleep(for: .milliseconds(300))
        let popover = try XCTUnwrap(controller.renamePopover)
        let popoverWindow = try XCTUnwrap(popover.contentViewController?.view.window)
        let titleScreenRect = window.convertToScreen(arrow.convert(arrow.bounds, to: nil))
        XCTAssertLessThan(abs(titleScreenRect.minY - popoverWindow.frame.maxY), 30)
        popover.close()

        document.rename(to: "改名后的文档.txt") { error in XCTAssertNil(error) }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(window.title, "改名后的文档.txt")
        XCTAssertEqual(arrow.title, "改名后的文档.txt")
        XCTAssertTrue(arrow.window === window)
        let originalFrame = window.frame
        defer { window.setFrame(originalFrame, display: false) }
        window.setContentSize(NSSize(width: 700, height: 420))
        try await Task.sleep(for: .milliseconds(100))
        frame.layoutSubtreeIfNeeded()
        XCTAssertEqual(arrow.convert(arrow.bounds, to: frame).midX, frame.bounds.midX, accuracy: 1)
    }

    @MainActor func testInitialWindowKeepsWidescreenSizeAfterLayout() throws {
        let document = TextDocument()
        document.makeWindowControllers()
        defer { document.close() }
        let window = try XCTUnwrap(document.windowControllers.first?.window)
        document.showWindows()
        window.contentView?.layoutSubtreeIfNeeded()
        let available = try XCTUnwrap(window.screen).visibleFrame.size
        XCTAssertEqual(window.frame.width / window.frame.height, 16.0 / 9.0, accuracy: 0.01)
        XCTAssertLessThanOrEqual(window.frame.width, available.width)
        XCTAssertLessThanOrEqual(window.frame.height, available.height)
        XCTAssertEqual(window.frame.width, min(1600, min(available.width * 0.9, available.height * 0.9 * 16 / 9)), accuracy: 1)
    }

    @MainActor func testReopenAfterClosingLastDocumentCreatesVisibleEditor() throws {
        let controller = try XCTUnwrap(NSDocumentController.shared as? DocumentController)
        controller.documents.forEach { $0.close() }
        let delegate = AppDelegate(documents: controller)
        controller.newDocument(nil)
        let original = try XCTUnwrap(controller.documents.first)
        original.close()
        XCTAssertTrue(controller.documents.isEmpty)
        defer { controller.documents.forEach { $0.close() } }

        XCTAssertFalse(delegate.applicationShouldHandleReopen(NSApp, hasVisibleWindows: false))
        XCTAssertEqual(controller.documents.count, 1)
        let reopened = try XCTUnwrap(controller.documents.first as? TextDocument)
        XCTAssertNotNil(reopened.editor)
        XCTAssertTrue(reopened.windowControllers.first?.window?.isVisible == true)

        XCTAssertTrue(delegate.applicationShouldHandleReopen(NSApp, hasVisibleWindows: true))
        XCTAssertEqual(controller.documents.count, 1)
    }

    @MainActor func testReopenReusesExistingHiddenDocument() throws {
        let controller = try XCTUnwrap(NSDocumentController.shared as? DocumentController)
        controller.documents.forEach { $0.close() }
        let delegate = AppDelegate(documents: controller)
        controller.newDocument(nil)
        defer { controller.documents.forEach { $0.close() } }
        let document = try XCTUnwrap(controller.documents.first)
        let window = try XCTUnwrap(document.windowControllers.first?.window)
        window.orderOut(nil)

        XCTAssertFalse(delegate.applicationShouldHandleReopen(NSApp, hasVisibleWindows: false))
        XCTAssertEqual(controller.documents.count, 1)
        XCTAssertTrue(controller.documents.first === document)
        XCTAssertTrue(window.isVisible)
    }
}
