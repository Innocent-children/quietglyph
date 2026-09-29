import XCTest
@testable import QuietGlyph

final class ReplacementTests: XCTestCase {
    func testOpenFileIsSkippedWhileClosedFilePreservesEncoding() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let a = folder.appendingPathComponent("open.txt"), b = folder.appendingPathComponent("closed.txt")
        var metadata = DocumentMetadata(); metadata.encoding = .utf16LE; metadata.hasBOM = true
        try TextFileCodec.encode("猫\r\n", metadata: metadata).write(to: a)
        try TextFileCodec.encode("猫\r\n", metadata: metadata).write(to: b)
        var query = SearchQuery(); query.text = "猫"; query.replacement = "狗"; query.filePatterns = "*.txt"
        let search = await SearchService.directory(folder, query: query)
        XCTAssertEqual(search.results.count, 2)
        let result = await ReplacementOperation.apply(search.results, query: query, openURLs: [a.standardizedFileURL])
        XCTAssertEqual(result.changed, 1); XCTAssertEqual(result.failures.count, 1)
        XCTAssertEqual(try DocumentIO.read(a).text, "猫\r\n")
        let changed = try DocumentIO.read(b)
        XCTAssertEqual(changed.text, "狗\r\n")
        XCTAssertEqual(changed.metadata.encoding, .utf16LE)
        XCTAssertTrue(changed.metadata.hasBOM)
    }
}
