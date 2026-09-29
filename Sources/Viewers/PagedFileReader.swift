import Foundation

struct TextPage: Sendable {
    let start: UInt64
    let end: UInt64
    let text: String
}

final class PagedFileReader: @unchecked Sendable {
    let url: URL
    let size: UInt64
    let encoding: TextEncoding
    let hasBOM: Bool
    private let file: FileHandle
    private let initialStamp: FileStamp
    private let lock = NSLock()
    init(url: URL, encoding preferred: TextEncoding? = nil) throws {
        self.url = url
        initialStamp = try DocumentIO.stamp(url)
        size = initialStamp.size
        file = try FileHandle(forReadingFrom: url)
        let sample = try file.read(upToCount: 4096) ?? Data()
        var decoded: DecodedText?
        for trim in 0...min(4, sample.count) {
            if let result = try? FileCodec.decode(sample.dropLast(trim), preferred: preferred) { decoded = result; break }
        }
        encoding = preferred ?? decoded?.metadata.encoding ?? .utf8
        hasBOM = sample.starts(with: encoding.bom) && !encoding.bom.isEmpty
    }
    func raw(at offset: UInt64, count: Int) throws -> Data {
        lock.lock(); defer { lock.unlock() }
        guard try DocumentIO.stamp(url) == initialStamp else { throw EditorError.externalChange }
        try file.seek(toOffset: min(offset, size))
        return try file.read(upToCount: max(0, count)) ?? Data()
    }
    func page(at requested: UInt64, count: Int = 64 * 1024) throws -> TextPage {
        let unit: UInt64 = [.utf16LE, .utf16BE].contains(encoding) ? 2 : 1
        var start = min(requested, size)
        start -= start % unit
        var bytes = try raw(at: start, count: max(count, 8))
        if start == 0 && hasBOM { bytes = bytes.dropFirst(encoding.bom.count); start += UInt64(encoding.bom.count) }
        if encoding == .utf8 {
            while let first = bytes.first, first & 0xC0 == 0x80 { bytes.removeFirst(); start += 1 }
        }
        if unit == 2, start > 0, bytes.count >= 2 {
            let prefix = Array(bytes.prefix(2))
            let value = encoding == .utf16LE ? UInt16(prefix[0]) | UInt16(prefix[1]) << 8 : UInt16(prefix[0]) << 8 | UInt16(prefix[1])
            if (0xDC00...0xDFFF).contains(value) { bytes = bytes.dropFirst(2); start += 2 }
        }
        for trim in 0...min(4, bytes.count) {
            let candidate = bytes.dropLast(trim)
            if let text = String(data: candidate, encoding: encoding.value) {
                if text.hasSuffix("\r"), candidate.count > Int(unit), start + UInt64(candidate.count) < size {
                    return TextPage(start: start, end: start + UInt64(candidate.count) - unit, text: String(text.dropLast()))
                }
                return TextPage(start: start, end: start + UInt64(candidate.count), text: text)
            }
        }
        throw EditorError.decoding
    }
    func find(_ text: String, after offset: UInt64) async throws -> UInt64? {
        guard !text.isEmpty else { return nil }
        var metadata = DocumentMetadata(); metadata.encoding = encoding
        var cursor = min(offset, size)
        var overlap = ""
        while cursor < size {
            try Task.checkCancellation()
            let page = try self.page(at: cursor, count: 1024 * 1024)
            guard page.end > cursor else { throw EditorError.decoding }
            let overlapBytes = try FileCodec.encode(overlap, metadata: metadata).count
            let window = (overlap + page.text) as NSString
            let base = page.start - UInt64(overlapBytes)
            var searchRange = NSRange(location: 0, length: window.length)
            while searchRange.length > 0 {
                let found = window.range(of: text, options: .literal, range: searchRange)
                if found.location == NSNotFound { break }
                let prefix = window.substring(to: found.location)
                let position = base + UInt64(try FileCodec.encode(prefix, metadata: metadata).count)
                if position >= offset { return position }
                searchRange = NSRange(location: NSMaxRange(found), length: window.length - NSMaxRange(found))
            }
            overlap = String((window as String).suffix((text as NSString).length))
            cursor = page.end
        }
        return nil
    }
    func findBytes(_ needle: Data, after offset: UInt64) async throws -> UInt64? {
        guard !needle.isEmpty else { return nil }
        var cursor = min(offset, size)
        var overlap = Data()
        while cursor < size {
            try Task.checkCancellation()
            let block = try raw(at: cursor, count: 1024 * 1024)
            guard !block.isEmpty else { break }
            var window = overlap; window.append(block)
            if let range = window.range(of: needle) { return cursor - UInt64(overlap.count) + UInt64(range.lowerBound) }
            overlap = window.suffix(max(0, needle.count - 1))
            cursor += UInt64(block.count)
        }
        return nil
    }
    deinit { try? file.close() }
}
