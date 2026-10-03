import XCTest
@testable import Inkline

final class BatchSearchTests: XCTestCase {
    func testOrderedRulesAndEmptyReplacement() throws {
        let rules = [BatchSearchRule(find: "cat", replace: "dog"), BatchSearchRule(find: "dog", replace: "")]
        let changes = try BatchSearchRule.edits(rules, text: "cat dog", ranges: [NSRange(location: 0, length: 7)])
        XCTAssertEqual(try EditTransaction.applying(changes.edits, to: "cat dog").text, " ")
        XCTAssertEqual(changes.occurrences, 3)
        XCTAssertThrowsError(try BatchSearchRule.edits([BatchSearchRule()], text: "a", ranges: [NSRange(location: 0, length: 1)]))
    }
    func testOriginalINIColumnsRoundTripSpacesCommaEscapesAndEmptyValue() throws {
        let rules = [BatchSearchRule(find: "two words, \"猫\"", replace: ""), BatchSearchRule(find: "\\n", replace: "@value\t\n")]
        let decoded = try BatchSearchRule.importText(BatchSearchRule.exportText(rules))
        XCTAssertEqual(decoded.map(\.find), rules.map(\.find)); XCTAssertEqual(decoded.map(\.replace), rules.map(\.replace))
        XCTAssertEqual(try BatchSearchRule.importText("[General]\nfind=a, b\nreplace=c, d\n").map(\.replace), ["c", "d"])
        XCTAssertThrowsError(try BatchSearchRule.importText("[General]\nfind=a,b\nreplace=c"))
    }
}
