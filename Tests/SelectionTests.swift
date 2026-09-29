import XCTest
@testable import QuietGlyph

final class SelectionTests: XCTestCase {
    func testRectangleClampsShortLinesWithoutSplittingEmoji() {
        let model = SelectionController()
        let text = "abcd\nx\n🙂xyz" as NSString
        model.rectangle(from: 0, to: 2, columns: 1...3, text: text)
        XCTAssertEqual(model.ranges.count, 3)
        XCTAssertEqual(model.ranges[0], NSRange(location: 1, length: 2))
        XCTAssertEqual(model.ranges[1], NSRange(location: 6, length: 0))
        XCTAssertEqual(model.ranges[2], NSRange(location: 7, length: 3))
    }
    func testDuplicateAndOverlappingSelectionsAreRemoved() {
        let model = SelectionController()
        model.set([NSRange(location: 0, length: 2), NSRange(location: 1, length: 2), NSRange(location: 0, length: 2)], text: "abcd")
        XCTAssertEqual(model.ranges, [NSRange(location: 0, length: 2)])
    }
    func testDisplayColumnsSplitTabsOnlyOnWriteAndPadShortLines() throws {
        let model = SelectionController(), text = "abcd\nx" as NSString
        model.rectangle(from: 0, to: 1, columns: 4...4, text: text)
        let result = try EditTransaction.applying(model.replacements(["#", "#"], text: text, tabWidth: 4), to: text as String)
        XCTAssertEqual(result.text, "abcd#\nx   #")
        let edit = ColumnGeometry.edit(2...2, in: "\tx", replacement: "#")
        XCTAssertEqual(try EditTransaction.applying([edit], to: "\tx").text, "  #  x")
        XCTAssertEqual(ColumnGeometry.column(at: 4, in: "e\u{301}🙂"), 3)
    }
    func testMultiCaretMovementKeepsAnchorsAndPreferredColumns() {
        let model = SelectionController(), text = "abcd\nx\nabcd\nx" as NSString
        model.set([NSRange(location: 3, length: 0), NSRange(location: 10, length: 0)], text: text)
        model.move(.down, extending: false, text: text, tabWidth: 4)
        XCTAssertEqual(model.ranges.map(\.location), [6, 13])
        model.move(.up, extending: true, text: text, tabWidth: 4)
        XCTAssertEqual(model.ranges, [NSRange(location: 3, length: 3), NSRange(location: 10, length: 3)])
        model.move(.down, extending: true, text: text, tabWidth: 4)
        XCTAssertTrue(model.ranges.allSatisfy { $0.length == 0 })
    }
}
