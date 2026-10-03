import XCTest
@testable import Inkline

final class FormattingTests: XCTestCase {
    func testJSONAndXMLFormattingAndErrors() throws {
        let json = try StructuredTextFormatter.json("{\"中文\":[1,true]}")
        XCTAssertTrue(json.contains("中文"))
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: Data(json.utf8)))
        XCTAssertTrue(try StructuredTextFormatter.xml("<root><value>你好</value></root>").contains("你好"))
        XCTAssertThrowsError(try StructuredTextFormatter.json("{broken"))
        XCTAssertThrowsError(try StructuredTextFormatter.xml("<root>"))
    }
    func testDigestsMatchKnownUTF8Input() {
        let value = ChecksumService.digest(Data("abc".utf8))
        XCTAssertTrue(value.contains("900150983cd24fb0d6963f7d28e17f72"))
        XCTAssertTrue(value.contains("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"))
    }
}
