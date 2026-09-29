import Foundation

enum LineCommand: String, CaseIterable {
    case duplicate = "Duplicate Lines", delete = "Delete Lines", removeEmpty = "Remove Empty Lines"
    case removeBlank = "Remove Blank Lines", unique = "Remove Duplicate Lines", consecutive = "Remove Consecutive Duplicates"
    case reverse = "Reverse Lines", shuffle = "Shuffle Lines", join = "Join Lines", split = "Split Lines"
    case sortAscending = "Sort A–Z", sortDescending = "Sort Z–A", sortIgnoreCase = "Sort A–Z (Ignore Case)"
    case sortIgnoreCaseDescending = "Sort Z–A (Ignore Case)", integers = "Sort Integers Ascending"
    case integersDescending = "Sort Integers Descending", decimals = "Sort Decimals Ascending"
    case decimalsDescending = "Sort Decimals Descending", commaDecimals = "Sort Comma Decimals Ascending"
    case commaDecimalsDescending = "Sort Comma Decimals Descending"
}

enum LineCommands {
    static func mapLines(_ text: String, transform: (String) -> String) -> String {
        let source = text as NSString
        return TextRanges.lines(source).filter { $0.length > 0 }.map { range in
            let content = TextRanges.lineContent(range, in: source)
            let ending = source.substring(with: NSRange(location: NSMaxRange(content), length: NSMaxRange(range) - NSMaxRange(content)))
            return transform(source.substring(with: content)) + ending
        }.joined()
    }

    static func apply(_ command: LineCommand, to text: String, ending: LineEnding, width: Int = 100, columns: ClosedRange<Int>? = nil, tabWidth: Int = 4) -> String {
        let source = text as NSString
        let hasFinalEnding = text.hasSuffix("\r\n") || text.hasSuffix("\n") || text.hasSuffix("\r")
        var lines = TextRanges.lines(source).filter { $0.length > 0 }.map { source.substring(with: TextRanges.lineContent($0, in: source)) }
        if lines.isEmpty { lines = [""] }
        switch command {
        case .duplicate: lines = lines.flatMap { [$0, $0] }
        case .delete: lines = []
        case .removeEmpty: lines.removeAll { $0.isEmpty }
        case .removeBlank: lines.removeAll { $0.trimmingCharacters(in: .whitespaces).isEmpty }
        case .unique:
            var seen = Set<String>(); lines = lines.filter { seen.insert($0).inserted }
        case .consecutive:
            var previous: String?
            lines = lines.filter { value in defer { previous = value }; return previous != value }
        case .reverse: lines.reverse()
        case .shuffle: lines.shuffle()
        case .join: return lines.joined(separator: " ") + (hasFinalEnding ? ending.text : "")
        case .split:
            lines = lines.flatMap { line -> [String] in
                var remaining = line[...]
                var result: [String] = []
                while remaining.count > max(1, width) {
                    let end = remaining.index(remaining.startIndex, offsetBy: max(1, width))
                    result.append(String(remaining[..<end]))
                    remaining = remaining[end...]
                }
                result.append(String(remaining))
                return result
            }
        default:
            let descending = [.sortDescending, .sortIgnoreCaseDescending, .integersDescending, .decimalsDescending, .commaDecimalsDescending].contains(command)
            let numeric = [.integers, .integersDescending, .decimals, .decimalsDescending, .commaDecimals, .commaDecimalsDescending].contains(command)
            let ignoreCase = [.sortIgnoreCase, .sortIgnoreCaseDescending].contains(command)
            let comma = [.commaDecimals, .commaDecimalsDescending].contains(command)
            func key(_ line: String) -> String {
                guard let columns else { return line }
                let range = ColumnGeometry.range(columns, in: line, tabWidth: tabWidth)
                return (line as NSString).substring(with: range)
            }
            lines = lines.enumerated().sorted { lhs, rhs in
                let result: ComparisonResult
                let left = key(lhs.element), right = key(rhs.element)
                if numeric {
                    let l = left.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: comma ? "," : "\u{FFFF}", with: ".")
                    let r = right.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: comma ? "," : "\u{FFFF}", with: ".")
                    if let a = Decimal(string: l, locale: Locale(identifier: "en_US_POSIX")), let b = Decimal(string: r, locale: Locale(identifier: "en_US_POSIX")) {
                        result = a == b ? .orderedSame : a < b ? .orderedAscending : .orderedDescending
                    } else { result = left.compare(right, options: .numeric) }
                } else { result = left.compare(right, options: ignoreCase ? .caseInsensitive : []) }
                if result == .orderedSame { return lhs.offset < rhs.offset }
                return result == (descending ? .orderedDescending : .orderedAscending)
            }.map(\.element)
        }
        return lines.joined(separator: ending.text) + (hasFinalEnding && !lines.isEmpty ? ending.text : "")
    }
}
