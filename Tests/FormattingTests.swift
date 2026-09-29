import XCTest
@testable import QuietGlyph

final class FormattingTests: XCTestCase {
    func testJSONAndXMLFormattingAndErrors() throws {
        let json = try FormatService.json("{\"中文\":[1,true]}")
        XCTAssertTrue(json.contains("中文"))
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: Data(json.utf8)))
        XCTAssertTrue(try FormatService.xml("<root><value>你好</value></root>").contains("你好"))
        XCTAssertThrowsError(try FormatService.json("{broken"))
        XCTAssertThrowsError(try FormatService.xml("<root>"))
    }
    func testDigestsMatchKnownUTF8Input() {
        let value = ChecksumService.digest(Data("abc".utf8))
        XCTAssertTrue(value.contains("900150983cd24fb0d6963f7d28e17f72"))
        XCTAssertTrue(value.contains("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"))
    }
}
