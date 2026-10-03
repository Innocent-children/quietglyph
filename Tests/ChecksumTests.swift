import XCTest
import CryptoKit
@testable import Inkline

final class ChecksumTests: XCTestCase {
    func testKnownVectorsAndRateBoundary() {
        let empty = ChecksumService.digest(Data())
        XCTAssertTrue(empty.contains("MD4: 31d6cfe0d16ae931b73c59d7e0c089c0"))
        XCTAssertTrue(empty.contains("SHA3-256: a7ffc6f8bf1ed76651c14756a061d662f580ff4de43b49fa82d80a4b80f8434a"))
        XCTAssertTrue(empty.contains("Keccak-256: c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470"))
        let abc = ChecksumService.digest(Data("abc".utf8))
        XCTAssertTrue(abc.contains("MD4: a448017aaf21d8525fc10ae87aa6729d"))
        XCTAssertTrue(abc.contains("SHA3-256: 3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532"))
        XCTAssertTrue(abc.contains("Keccak-256: 4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45"))
        if #available(macOS 26, *) {
            for size in [1, 135, 136, 137, 271, 272, 4097] {
                let data = Data((0..<size).map { UInt8(truncatingIfNeeded: $0) })
                var hash = Keccak256Digest(sha3: true)
                for chunk in stride(from: 0, to: size, by: 73) { hash.update(data.subdata(in: chunk..<min(size, chunk + 73))) }
                XCTAssertEqual(hash.finalize(), Array(SHA3_256.hash(data: data)), "size \(size)")
            }
        }
    }
    func testFileDigestUsesRawEncodingAndBOMBytes() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        for encoding in [TextEncoding.utf8, .utf16LE, .gbk] {
            var metadata = DocumentMetadata(); metadata.encoding = encoding; metadata.hasBOM = !encoding.bom.isEmpty
            let bytes = try TextFileCodec.encode("中文\r\n", metadata: metadata); try bytes.write(to: url)
            let digest = try await ChecksumService.file(url)
            XCTAssertEqual(digest, ChecksumService.digest(bytes))
        }
    }
}
