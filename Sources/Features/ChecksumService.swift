import Foundation
import CryptoKit

enum ChecksumService {
    struct Hasher {
        var md4 = MD4Digest(), md5 = Insecure.MD5(), sha1 = Insecure.SHA1(), sha256 = SHA256(), sha512 = SHA512()
        var sha3 = Keccak256Digest(sha3: true), keccak = Keccak256Digest(sha3: false)
        mutating func update(_ data: Data) {
            md4.update(data); md5.update(data: data); sha1.update(data: data); sha256.update(data: data); sha512.update(data: data)
            sha3.update(data); keccak.update(data)
        }
        mutating func finalize() -> String {
            let values: [(String, [UInt8])] = [("MD4", md4.finalize()), ("MD5", Array(md5.finalize())), ("SHA-1", Array(sha1.finalize())),
                ("SHA-256", Array(sha256.finalize())), ("SHA-512", Array(sha512.finalize())), ("SHA3-256", sha3.finalize()), ("Keccak-256", keccak.finalize())]
            return values.map { $0.0 + ": " + $0.1.map { String(format: "%02x", $0) }.joined() }.joined(separator: "\n")
        }
    }
    static func digest(_ data: Data) -> String {
        var hash = Hasher(); hash.update(data); return hash.finalize()
    }
    static func file(_ url: URL, progress: @Sendable (UInt64, UInt64) async -> Void = { _, _ in }) async throws -> String {
        let stamp = try DocumentIO.stamp(url), file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var hash = Hasher(), processed: UInt64 = 0
        while true {
            try Task.checkCancellation()
            let block = try file.read(upToCount: 1024 * 1024) ?? Data()
            if block.isEmpty { break }
            hash.update(block); processed += UInt64(block.count); await progress(processed, stamp.size)
        }
        guard try DocumentIO.stamp(url) == stamp else { throw EditorError.externalChange }
        return hash.finalize()
    }
}
