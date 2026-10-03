import XCTest
import AppKit
@testable import Inkline

final class MarkdownRendererTests: XCTestCase {
    @MainActor func testMarkdownBlocksTablesImageAndUnicode() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures", isDirectory: true)
        let source = try String(contentsOf: root.appendingPathComponent("markdown-preview.md"), encoding: .utf8)
        let rendered = try MarkdownRenderer.render(source, baseURL: root)
        XCTAssertTrue(rendered.string.contains("Markdown 对照 🙂\n"))
        XCTAssertTrue(rendered.string.contains("•\t第一项")); XCTAssertTrue(rendered.string.contains("•\t嵌套项"))
        XCTAssertTrue(rendered.string.contains("1.\t编号一"))
        XCTAssertTrue(rendered.string.contains("let value = \"中文🙂\"\nprint(value)"))
        var imageCount = 0, tableCells = 0, links = 0
        rendered.enumerateAttributes(in: NSRange(location: 0, length: rendered.length)) { attributes, _, _ in
            if attributes[.attachment] != nil { imageCount += 1 }
            if let style = attributes[.paragraphStyle] as? NSParagraphStyle, !style.textBlocks.isEmpty { tableCells += 1 }
            if attributes[.link] != nil { links += 1 }
        }
        XCTAssertEqual(imageCount, 1); XCTAssertGreaterThanOrEqual(tableCells, 6); XCTAssertGreaterThan(links, 0)
        XCTAssertTrue(source.contains("# Markdown"))
    }
}
