import XCTest
@testable import QuietGlyph

final class RecoveryTests: XCTestCase {
    func testRecoveryIsSeparateFromSourceAndCanBeRemoved() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = RecoveryStore(directory: folder.appendingPathComponent("recovery"))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let source = folder.appendingPathComponent("source.txt")
        try Data("disk".utf8).write(to: source)
        let record = RecoveryRecord(id: UUID(), fileURL: source, title: "source.txt", text: "unsaved 中文🙂",
                                    metadata: DocumentMetadata(), savedAt: Date())
        try store.save(record)
        XCTAssertEqual(store.records().first?.text, record.text)
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "disk")
        store.remove(record.id)
        XCTAssertTrue(store.records().isEmpty)
    }
}
