import XCTest
@testable import Inkline

final class HexViewTests: XCTestCase {
    func testOffsetsBytesAndASCIIRendering() {
        let output = HexViewController.format(Data([0, 65, 255]), offset: 0x1234)
        XCTAssertTrue(output.contains("000000001234"))
        XCTAssertTrue(output.contains("00 41 FF"))
        XCTAssertTrue(output.contains("│.A.│"))
    }
}
