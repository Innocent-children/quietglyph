import Foundation

enum ColumnCommands {
    static func removeBlockComment(_ text: String, selections: [NSRange], start: String, end: String) -> [TextEdit] {
        guard !start.isEmpty, !end.isEmpty else { return [] }
        let source = text as NSString
        var ranges: [NSRange] = []
        for selection in selections where TextRanges.valid(selection, in: source) {
            let searchEnd = min(source.length, selection.location + start.utf16.count)
            let open = source.range(of: start, options: .backwards, range: NSRange(location: 0, length: searchEnd))
            guard open.location != NSNotFound else { continue }
            let close = source.range(of: end, range: NSRange(location: NSMaxRange(open), length: source.length - NSMaxRange(open)))
            guard close.location != NSNotFound, selection.location <= NSMaxRange(close), NSMaxRange(selection) <= NSMaxRange(close) else { continue }
            for range in [open, close] where !ranges.contains(range) { ranges.append(range) }
        }
        return ranges.map { TextEdit(range: $0, replacement: "") }
    }
    static func values(count: Int, start: Int, increment: Int, repeatCount: Int, radix: Int, prefix: String, uppercase: Bool = true) -> [String] {
        let base = [2, 8, 10, 16].contains(radix) ? radix : 10
        return (0..<max(0, count)).map { i in
            let value = start.addingReportingOverflow((i / max(1, repeatCount)).multipliedReportingOverflow(by: increment).partialValue).partialValue
            return prefix + String(value, radix: base, uppercase: uppercase)
        }
    }
    static func comment(_ text: String, prefix: String) -> String {
        guard !prefix.isEmpty else { return text }
        let nonempty = text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let remove = !nonempty.isEmpty && nonempty.allSatisfy { $0.trimmingCharacters(in: .whitespaces).hasPrefix(prefix) }
        return LineCommands.mapLines(text) { line in
            let spaces = line.prefix(while: { $0 == " " || $0 == "\t" })
            let rest = line.dropFirst(spaces.count)
            if remove, rest.hasPrefix(prefix) {
                var value = rest.dropFirst(prefix.count)
                if value.first == " " { value = value.dropFirst() }
                return String(spaces) + value
            }
            return String(spaces) + prefix + " " + rest
        }
    }
}
