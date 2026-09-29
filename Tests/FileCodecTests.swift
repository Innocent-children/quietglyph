import XCTest
@testable import QuietGlyph

final class FileCodecTests: XCTestCase {
    func testEncodingBOMAndLineEndingsRoundTrip() throws {
        for encoding in TextEncoding.allCases {
            for ending in LineEnding.allCases {
                var metadata = DocumentMetadata(); metadata.encoding = encoding; metadata.lineEnding = ending
                metadata.hasBOM = !encoding.bom.isEmpty
                let text = "第一行" + ending.text + "second 123" + ending.text
                let data = try FileCodec.encode(text, metadata: metadata)
                let decoded = try FileCodec.decode(data, preferred: encoding)
                XCTAssertEqual(decoded.text, text, encoding.title)
                XCTAssertEqual(decoded.metadata.hasBOM, metadata.hasBOM)
                XCTAssertEqual(decoded.metadata.lineEnding, ending)
            }
        }
    }
    func testUnicodeIsNotSilentlyLostInGBK() throws {
        var metadata = DocumentMetadata(); metadata.encoding = .gbk
        XCTAssertThrowsError(try FileCodec.encode("🙂", metadata: metadata))
        metadata.encoding = .gb18030
        let data = try FileCodec.encode("🙂", metadata: metadata)
        XCTAssertEqual(try FileCodec.decode(data, preferred: .gb18030).text, "🙂")
    }
    func testInvalidUTF8FailsWhenExplicitlyChosen() {
        XCTAssertThrowsError(try FileCodec.decode(Data([0xFF, 0x80, 0x81]), preferred: .utf8))
    }
    func testMixedLineEndingsRemainUnchangedUntilConverted() throws {
        let text = "a\r\nb\nc\r"
        let decoded = try FileCodec.decode(Data(text.utf8))
        XCTAssertEqual(try FileCodec.encode(decoded.text, metadata: decoded.metadata), Data(text.utf8))
        XCTAssertEqual(LineEnding.crlf.converting(text), "a\r\nb\r\nc\r\n")
    }
}
