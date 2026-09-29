import Foundation

struct LineIndex: Sendable {
    struct Entry: Sendable { var line: UInt64; var offset: UInt64 }
    var entries: [Entry]
    var count: UInt64
    static func build(reader: PagedFileReader) async throws -> LineIndex {
        let unit = [.utf16LE, .utf16BE].contains(reader.encoding) ? 2 : 1
        var offset: UInt64 = reader.hasBOM ? UInt64(reader.encoding.bom.count) : 0
        var entries = [Entry(line: 1, offset: offset)]
        var line: UInt64 = 1
        var previousCR = false
        while offset < reader.size {
            try Task.checkCancellation()
            let bytes = [UInt8](try reader.raw(at: offset, count: 1024 * 1024))
            guard !bytes.isEmpty else { break }
            var i = 0
            while i + unit <= bytes.count {
                let ch: UInt16
                if unit == 1 { ch = UInt16(bytes[i]) }
                else if reader.encoding == .utf16LE { ch = UInt16(bytes[i]) | UInt16(bytes[i + 1]) << 8 }
                else { ch = UInt16(bytes[i]) << 8 | UInt16(bytes[i + 1]) }
                let next = offset + UInt64(i + unit)
                if ch == 10 && previousCR {
                    if entries.last?.line == line { entries[entries.count - 1].offset = next }
                } else if ch == 10 || ch == 13 {
                    line += 1
                    if (line - 1) % 512 == 0 { entries.append(Entry(line: line, offset: next)) }
                }
                previousCR = ch == 13
                i += unit
            }
            offset += UInt64(bytes.count)
        }
        return LineIndex(entries: entries, count: line)
    }
    func offset(for target: UInt64, reader: PagedFileReader) async throws -> UInt64 {
        let goal = min(max(1, target), count)
        let entry = entries.last(where: { $0.line <= goal }) ?? entries[0]
        if entry.line == goal { return entry.offset }
        var line = entry.line, offset = entry.offset
        var previousCR = false
        let unit = [.utf16LE, .utf16BE].contains(reader.encoding) ? 2 : 1
        while offset < reader.size {
            try Task.checkCancellation()
            let data = [UInt8](try reader.raw(at: offset, count: 64 * 1024))
            for i in stride(from: 0, to: max(0, data.count - unit + 1), by: unit) {
                let ch: UInt16 = unit == 1 ? UInt16(data[i]) :
                    reader.encoding == .utf16LE ? UInt16(data[i]) | UInt16(data[i + 1]) << 8 : UInt16(data[i]) << 8 | UInt16(data[i + 1])
                if previousCR {
                    if line == goal { return offset + UInt64(i) + (ch == 10 ? UInt64(unit) : 0) }
                    if ch == 10 { previousCR = false; continue }
                }
                if ch == 10 || ch == 13 { line += 1; if ch == 10 && line == goal { return offset + UInt64(i + unit) } }
                previousCR = ch == 13
            }
            if data.isEmpty { break }
            offset += UInt64(data.count)
        }
        return reader.size
    }
}
