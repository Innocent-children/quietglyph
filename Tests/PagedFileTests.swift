import XCTest
@testable import QuietGlyph

final class PagedFileTests: XCTestCase {
    func testPageDoesNotSplitCRLFOrStartOnUTF16LowSurrogate() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("1234567\r\nnext".utf8).write(to: url)
        var reader = try PagedFileReader(url: url)
        let first = try reader.page(at: 0, count: 8)
        XCTAssertEqual(first.text, "1234567")
        XCTAssertTrue(try reader.page(at: first.end).text.hasPrefix("\r\n"))
        var metadata = DocumentMetadata(); metadata.encoding = .utf16LE
        try TextFileCodec.encode("a🙂b", metadata: metadata).write(to: url)
        reader = try PagedFileReader(url: url, encoding: .utf16LE)
        XCTAssertEqual(try reader.page(at: 4).text, "b")
    }
    func testPagesPreserveUnicodeAcrossBoundaries() throws {
        for encoding in [TextEncoding.utf8, .utf16LE, .utf16BE, .gb18030] {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: url) }
            var metadata = DocumentMetadata(); metadata.encoding = encoding; metadata.hasBOM = !encoding.bom.isEmpty
            let source = String(repeating: "一🙂二\r\n", count: 60)
            try TextFileCodec.encode(source, metadata: metadata).write(to: url)
            let reader = try PagedFileReader(url: url, encoding: encoding)
            var output = "", cursor: UInt64 = 0
            while cursor < reader.size {
                let page = try reader.page(at: cursor, count: 31)
                XCTAssertGreaterThan(page.end, cursor)
                output += page.text; cursor = page.end
            }
            XCTAssertEqual(output, source, encoding.title)
        }
    }
    func testSparseFileLineIndexAndStreamingFind() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let source = (1...1400).map { "line\($0)\r\n" }.joined()
        try Data(source.utf8).write(to: url)
        let reader = try PagedFileReader(url: url)
        let index = try await FileLineIndex.build(reader: reader)
        XCTAssertEqual(index.count, 1401)
        let offset = try await index.offset(for: 1025, reader: reader)
        XCTAssertTrue(try reader.page(at: offset).text.hasPrefix("line1025\r\n"))
        let found = try await reader.find("line1100", after: 0)
        XCTAssertNotNil(found)
        XCTAssertTrue(try reader.page(at: found!).text.hasPrefix("line1100"))
    }
}
