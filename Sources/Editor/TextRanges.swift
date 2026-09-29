import Foundation

enum TextRanges {
    static func valid(_ range: NSRange, in text: NSString) -> Bool {
        range.location != NSNotFound && range.location >= 0 && range.length >= 0 &&
        range.location <= text.length && range.length <= text.length - range.location
    }
    static func composed(_ range: NSRange, in text: NSString) -> NSRange {
        guard valid(range, in: text) else { return NSRange(location: 0, length: 0) }
        if range.length > 0 { return text.rangeOfComposedCharacterSequences(for: range) }
        if range.location == 0 || range.location == text.length { return range }
        let containing = text.rangeOfComposedCharacterSequence(at: range.location)
        return NSRange(location: containing.location, length: 0)
    }
    static func lines(_ text: NSString) -> [NSRange] {
        guard text.length > 0 else { return [NSRange(location: 0, length: 0)] }
        var result: [NSRange] = []
        var offset = 0
        while offset < text.length {
            let range = text.lineRange(for: NSRange(location: offset, length: 0))
            result.append(range)
            offset = NSMaxRange(range)
        }
        if text.hasSuffix("\n") || text.hasSuffix("\r") { result.append(NSRange(location: text.length, length: 0)) }
        return result
    }
    static func lineNumber(at offset: Int, in text: NSString) -> Int {
        let safe = min(max(0, offset), text.length)
        return lines(text).lastIndex(where: { $0.location <= safe }).map { $0 + 1 } ?? 1
    }
    static func lineContent(_ range: NSRange, in text: NSString) -> NSRange {
        var end = NSMaxRange(range)
        while end > range.location && [10, 13].contains(text.character(at: end - 1)) { end -= 1 }
        return NSRange(location: range.location, length: end - range.location)
    }
}
