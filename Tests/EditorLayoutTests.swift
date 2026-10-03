import XCTest
import AppKit
@testable import Inkline

final class EditorLayoutTests: XCTestCase {
    @MainActor func testLineNumberFontAndGutterFollowZoomAndLineCount() throws {
        try withEditor { editor, _, window, ruler in
            XCTAssertEqual(ruler.labelFont.pointSize, 13)
            let initialWidth = ruler.ruleThickness
            SettingsStore.shared.values.fontSize = 24
            window.contentView?.layoutSubtreeIfNeeded()
            XCTAssertEqual(ruler.labelFont.pointSize, 24)
            XCTAssertGreaterThan(ruler.ruleThickness, initialWidth)
            let zoomedWidth = ruler.ruleThickness
            editor.paste(String(repeating: "line\n", count: 1000))
            window.contentView?.layoutSubtreeIfNeeded()
            XCTAssertGreaterThan(ruler.ruleThickness, zoomedWidth)
            try assertAligned(ruler.visibleLines(), editor: editor, ruler: ruler)
        }
    }

    @MainActor private struct Fixture {
        let preferences: Preferences
        let document: TextDocument
        let editor: EditorController
        let window: NSWindow
        let ruler: LineNumberRuler

        init(_ text: String = "") throws {
            preferences = SettingsStore.shared.values
            SettingsStore.shared.values = Preferences()
            document = TextDocument()
            document.initialText = text
            editor = EditorController(document: document)
            document.editor = editor
            window = NSWindow(contentRect: NSRect(x: 200, y: 300, width: 600, height: 400),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentViewController = editor
            window.setContentSize(NSSize(width: 600, height: 400))
            window.contentView?.layoutSubtreeIfNeeded()
            editor.textView.layoutSubtreeIfNeeded()
            editor.setSelections([NSRange(location: 0, length: 0)])
            ruler = try XCTUnwrap(editor.scrollView.verticalRulerView as? LineNumberRuler)
        }

        func close() {
            window.close()
            document.close()
            SettingsStore.shared.values = preferences
        }
    }

    @MainActor private func withEditor(_ text: String = "", _ body: (EditorController, TextDocument, NSWindow, LineNumberRuler) throws -> Void) throws {
        let fixture = try Fixture(text)
        defer { fixture.close() }
        try body(fixture.editor, fixture.document, fixture.window, fixture.ruler)
    }

    @MainActor func testPasteAndUndoUpdateLineRangesImmediately() throws {
        try withEditor("a\nb\nc\n") { editor, document, _, _ in
            let undo = try XCTUnwrap(document.undoManager)
            undo.groupsByEvent = false
            undo.beginUndoGrouping()
            editor.paste("first\nsecond\n")
            undo.endUndoGrouping()
            XCTAssertEqual(editor.lineRanges.map(\.location), [0, 6, 13, 15, 17, 19])
            undo.undo()
            XCTAssertEqual(editor.lineRanges.map(\.location), [0, 2, 4, 6])
            undo.redo()
            XCTAssertEqual(editor.lineRanges.map(\.location), [0, 6, 13, 15, 17, 19])
            editor.setSelections([NSRange(location: 0, length: editor.source.length)])
            undo.beginUndoGrouping()
            editor.paste("short")
            undo.endUndoGrouping()
            XCTAssertEqual(editor.lineRanges, [NSRange(location: 0, length: 5)])
        }
    }

    @MainActor func testPasteIntoEmptyDocumentRetainsTypographyThroughUndo() throws {
        try withEditor { editor, document, _, _ in
            SettingsStore.shared.values.fontSize = 19
            SettingsStore.shared.values.tabWidth = 7
            let font = try XCTUnwrap(editor.textAttributes[.font] as? NSFont)
            let paragraph = try XCTUnwrap(editor.textAttributes[.paragraphStyle] as? NSParagraphStyle)
            let undo = try XCTUnwrap(document.undoManager)
            undo.groupsByEvent = false
            @MainActor func assertTypography() throws {
                let storage = try XCTUnwrap(editor.textView.textStorage)
                storage.enumerateAttributes(in: NSRange(location: 0, length: storage.length)) { attributes, _, _ in
                    XCTAssertEqual(attributes[.font] as? NSFont, font)
                    let actual = attributes[.paragraphStyle] as? NSParagraphStyle
                    XCTAssertEqual(actual?.defaultTabInterval, paragraph.defaultTabInterval)
                    XCTAssertEqual(actual?.tabStops, paragraph.tabStops)
                }
            }
            undo.beginUndoGrouping()
            editor.paste("\tfirst🙂\nsecond")
            undo.endUndoGrouping()
            try assertTypography()
            undo.undo()
            XCTAssertEqual(editor.textView.string, "")
            XCTAssertEqual(editor.textView.typingAttributes[.font] as? NSFont, font)
            undo.redo()
            try assertTypography()
            editor.setSelections([NSRange(location: 0, length: editor.source.length)])
            undo.beginUndoGrouping()
            editor.deleteSelections(backwards: true)
            editor.textView.insertText("again", replacementRange: NSRange(location: NSNotFound, length: 0))
            undo.endUndoGrouping()
            try assertTypography()
        }
    }

    @MainActor func testWrappedLineOutsideViewportDoesNotHideFollowingLineNumbers() throws {
        try withEditor { editor, _, window, ruler in
            let prefix = String(repeating: "short line\n", count: 1000)
            editor.paste(prefix + String(repeating: "long wrapped text ", count: 1000) + "\n" + String(repeating: "short\n", count: 5))
            window.contentView?.layoutSubtreeIfNeeded()
            XCTAssertEqual(editor.lineRanges.count, 1007)
            XCTAssertNil(editor.textView.localRect(NSRange(location: prefix.utf16.count, length: 0)))
            let lines = ruler.visibleLines()
            XCTAssertEqual(lines.map(\.number), [1002, 1003, 1004, 1005, 1006, 1007])
            try assertAligned(lines, editor: editor, ruler: ruler)
            let rulerBitmap = try XCTUnwrap(ruler.bitmapImageRepForCachingDisplay(in: ruler.bounds))
            ruler.cacheDisplay(in: ruler.bounds, to: rulerBitmap)
            let background = try XCTUnwrap(rulerBitmap.colorAt(x: 0, y: 0)?.usingColorSpace(.deviceRGB))
            let scale = CGFloat(rulerBitmap.pixelsHigh) / ruler.bounds.height
            for line in lines {
                let rows = Int(line.rect.minY * scale)..<Int(line.rect.maxY * scale)
                let hasInk = rows.contains { y in
                    (Int(10 * scale)..<Int(38 * scale)).contains { x in
                        guard let color = rulerBitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { return false }
                        return abs(color.redComponent - background.redComponent) > 0.1
                    }
                }
                XCTAssertTrue(hasInk, "Line \(line.number) must be painted in the ruler")
            }
            let rulerPNG = try XCTUnwrap(rulerBitmap.representation(using: .png, properties: [:]))
            let rulerScreenshot = XCTAttachment(data: rulerPNG, uniformTypeIdentifier: "public.png")
            rulerScreenshot.name = "Wrapped paste ruler rendering"
            rulerScreenshot.lifetime = .keepAlways
            add(rulerScreenshot)
            let bitmap = try XCTUnwrap(editor.view.bitmapImageRepForCachingDisplay(in: editor.view.bounds))
            editor.view.cacheDisplay(in: editor.view.bounds, to: bitmap)
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            let screenshot = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
            screenshot.name = "Wrapped paste editor rendering"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
    }

    @MainActor func testThousandLinePasteReplacementUndoAndRedoWithoutResizing() throws {
        try withEditor { editor, document, window, ruler in
            let undo = try XCTUnwrap(document.undoManager)
            undo.groupsByEvent = false
            let text = (1...1200).map { "\($0)\t正文🙂 " + String(repeating: "content ", count: $0 % 11 == 0 ? 50 : 3) + "\n" }.joined()
            let originalFrame = window.frame
            undo.beginUndoGrouping()
            editor.paste(text)
            undo.endUndoGrouping()
            XCTAssertEqual(editor.lineRanges.count, 1201)
            window.contentView?.layoutSubtreeIfNeeded()
            XCTAssertTrue(ruler.visibleLines().contains { $0.number == 1201 })
            try assertAligned(ruler.visibleLines(), editor: editor, ruler: ruler)
            editor.setSelections([NSRange(location: 0, length: editor.source.length)])
            undo.beginUndoGrouping()
            editor.paste(String(repeating: "replacement\n", count: 150))
            undo.endUndoGrouping()
            XCTAssertEqual(editor.lineRanges.count, 151)
            window.contentView?.layoutSubtreeIfNeeded()
            XCTAssertTrue(ruler.visibleLines().contains { $0.number == 151 })
            try assertAligned(ruler.visibleLines(), editor: editor, ruler: ruler)
            undo.undo()
            XCTAssertEqual(editor.textView.string, text)
            XCTAssertEqual(editor.lineRanges.count, 1201)
            window.contentView?.layoutSubtreeIfNeeded()
            XCTAssertFalse(ruler.visibleLines().isEmpty)
            try assertAligned(ruler.visibleLines(), editor: editor, ruler: ruler)
            undo.redo()
            XCTAssertEqual(editor.lineRanges.count, 151)
            window.contentView?.layoutSubtreeIfNeeded()
            try assertAligned(ruler.visibleLines(), editor: editor, ruler: ruler)
            XCTAssertEqual(window.frame, originalFrame)
        }
    }

    @MainActor func testLargePasteRemainsAlignedAfterDeferredHighlighting() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let editor = fixture.editor
        let frame = fixture.window.frame
        editor.paste((1...1000).map { "line \($0) 中文🙂\n" }.joined())
        XCTAssertEqual(editor.lineRanges.count, 1001)
        for _ in 0..<2 {
            try await Task.sleep(for: .milliseconds(350))
            fixture.window.contentView?.layoutSubtreeIfNeeded()
            let lines = fixture.ruler.visibleLines()
            XCTAssertTrue(lines.contains { $0.number == 1001 })
            try assertAligned(lines, editor: editor, ruler: fixture.ruler)
            XCTAssertEqual(fixture.window.frame, frame)
        }
    }

    @MainActor func testLineNumbersFollowScrollingResizingAndAttributeLayout() throws {
        try withEditor { editor, _, window, ruler in
            editor.paste((0..<200).map { "\($0) " + String(repeating: "word ", count: $0 % 7 == 0 ? 100 : 3) + "\n" }.joined())
            for width: CGFloat in [600, 360, 800] {
                window.setContentSize(NSSize(width: width, height: 400))
                for line in [1, 90, 200] {
                    editor.goTo(line: line)
                    window.contentView?.layoutSubtreeIfNeeded()
                    let before = ruler.visibleLines()
                    XCTAssertTrue(before.contains { $0.number == line })
                    try assertAligned(before, editor: editor, ruler: ruler)
                    ruler.needsDisplay = false
                    editor.textView.textStorage?.addAttribute(.foregroundColor, value: NSColor.systemRed,
                                                             range: NSRange(location: 0, length: editor.source.length))
                    window.contentView?.layoutSubtreeIfNeeded()
                    XCTAssertTrue(ruler.needsDisplay)
                    let after = ruler.visibleLines()
                    XCTAssertFalse(after.isEmpty)
                    try assertAligned(after, editor: editor, ruler: ruler)
                }
            }
        }
    }

    @MainActor func testEmptyDocumentAndTrailingNewlineHaveLineNumbers() throws {
        for (text, expected) in [("", [1]), ("a", [1]), ("a\n", [1, 2]), ("a\r\nb\r\n", [1, 2, 3]), ("\n\n", [1, 2, 3])] {
            try withEditor(text) { editor, _, _, ruler in
                let lines = ruler.visibleLines()
                XCTAssertEqual(lines.map(\.number), expected, text.debugDescription)
                try assertAligned(lines, editor: editor, ruler: ruler)
            }
        }
    }

    @MainActor func testFoldedRegionLongerThan500LinesKeepsFollowingLineNumbers() throws {
        try withEditor("{\n" + String(repeating: "hidden\n", count: 600) + "}\n") { editor, _, window, ruler in
            var language = LanguageDefinition.plain
            language.folding = "braces"
            editor.language = language
            editor.folding.collapseAll()
            window.contentView?.layoutSubtreeIfNeeded()
            let lines = ruler.visibleLines()
            XCTAssertEqual(lines.map(\.number), [1, 602, 603])
            try assertAligned(lines, editor: editor, ruler: ruler)
        }
    }

    @MainActor private func assertAligned(_ lines: [LineNumberRuler.VisibleLine], editor: EditorController, ruler: LineNumberRuler,
                                         file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(Set(lines.map(\.number)).count, lines.count, file: file, line: line)
        for entry in lines {
            let native = try XCTUnwrap(editor.textView.localRect(NSRange(location: entry.range.location, length: 0)), file: file, line: line)
            let nativeInRuler = ruler.convert(native, from: editor.textView)
            let minY = max(entry.rect.minY, ruler.bounds.minY)
            let maxY = min(entry.rect.maxY, ruler.bounds.maxY)
            XCTAssertEqual(minY, nativeInRuler.minY, accuracy: 0.5, file: file, line: line)
            XCTAssertEqual(maxY - minY, nativeInRuler.height, accuracy: 0.5, file: file, line: line)
        }
        for (previous, next) in zip(lines, lines.dropFirst()) {
            XCTAssertGreaterThan(next.baseline, previous.baseline, file: file, line: line)
        }
    }
}
