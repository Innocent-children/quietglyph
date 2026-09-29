import XCTest
@testable import QuietGlyph

final class TextCommandsTests: XCTestCase {
    func testLineTransformsPreserveTerminators() {
        XCTAssertEqual(TextCommand.trimBoth.apply("  one \r\n two \r"), "one\r\ntwo\r")
        XCTAssertEqual(TextCommand.tabsToSpaces.apply("a\tb", tabWidth: 4), "a   b")
        XCTAssertEqual(LineCommands.apply(.unique, to: "a\r\nb\r\na\r\n", ending: .crlf), "a\r\nb\r\n")
        XCTAssertEqual(LineCommands.apply(.integers, to: "10\n2\n-3", ending: .lf), "-3\n2\n10")
        XCTAssertEqual(LineCommands.apply(.commaDecimals, to: "2,5\n1,9", ending: .lf), "1,9\n2,5")
    }
    func testCommentRoundTripAndColumnNumbers() {
        let text = "  one\n  two\n"
        let commented = ColumnCommands.comment(text, prefix: "//")
        XCTAssertEqual(ColumnCommands.comment(commented, prefix: "//"), text)
        XCTAssertEqual(ColumnCommands.values(count: 4, start: 15, increment: 1, repeatCount: 2, radix: 16, prefix: "0x"), ["0xF", "0xF", "0x10", "0x10"])
    }
}
