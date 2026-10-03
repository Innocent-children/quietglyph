import XCTest
@testable import Inkline

final class EditorToolsTests: XCTestCase {
    func testNavigationAndBlockCommentRemoval() throws {
        let history = NavigationHistory(); history.record(from: 0, to: 10); history.record(from: 10, to: 20)
        XCTAssertEqual(history.move(backwards: true), 10); XCTAssertEqual(history.move(backwards: true), 0)
        XCTAssertEqual(history.move(backwards: false), 10)
        history.record(from: 10, to: 30); XCTAssertNil(history.move(backwards: false))
        let source = "/*中文🙂*/"
        let edits = ColumnCommands.removeBlockComment(source, selections: [NSRange(location: 4, length: 0)], start: "/*", end: "*/")
        XCTAssertEqual(try EditTransaction.applying(edits, to: source).text, "中文🙂")
        let stats = TextStatistics(text: "猫🙂 \r\n")
        XCTAssertEqual(stats.characters, 4); XCTAssertEqual(stats.whitespace, 2); XCTAssertEqual(stats.lines, 2)
    }
}
