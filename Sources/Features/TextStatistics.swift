import Foundation

struct TextStatistics {
    var characters = 0
    var utf16Units = 0
    var words = 0
    var lines = 0
    var whitespace = 0
    var nonWhitespace: Int { characters - whitespace }
    init(text: String, ranges: [NSRange]? = nil) {
        let source = text as NSString
        for range in ranges ?? [NSRange(location: 0, length: source.length)] where TextRanges.valid(range, in: source) {
            let part = source.substring(with: range)
            characters += part.count; utf16Units += part.utf16.count
            whitespace += part.filter(\.isWhitespace).count
            lines += TextRanges.lines(part as NSString).count
            var count = 0
            part.enumerateSubstrings(in: part.startIndex..<part.endIndex, options: .byWords) { _, _, _, _ in count += 1 }
            words += count
        }
    }
}
