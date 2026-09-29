import Foundation

struct TextEdit: Equatable {
    var range: NSRange
    var replacement: String
}

struct AppliedEdits {
    var text: String
    var inverse: [TextEdit]
    var carets: [NSRange]
}

enum EditTransaction {
    static func normalized(_ edits: [TextEdit], in source: NSString) throws -> [TextEdit] {
        let sorted = edits.sorted { $0.range.location < $1.range.location }
        var end = -1
        var lastStart = -1
        for edit in sorted {
            guard TextRanges.valid(edit.range, in: source),
                  edit.range.location >= end, edit.range.location != lastStart,
                  TextRanges.composed(edit.range, in: source) == edit.range else { throw EditorError.invalidRange }
            end = NSMaxRange(edit.range)
            lastStart = edit.range.location
        }
        return sorted
    }
    static func applying(_ edits: [TextEdit], to text: String) throws -> AppliedEdits {
        let source = text as NSString
        let sorted = try normalized(edits, in: source)
        let output = NSMutableString(string: text)
        var inverse: [TextEdit] = []
        var carets: [NSRange] = []
        var delta = 0
        for edit in sorted {
            let length = (edit.replacement as NSString).length
            inverse.append(TextEdit(range: NSRange(location: edit.range.location + delta, length: length),
                                    replacement: source.substring(with: edit.range)))
            carets.append(NSRange(location: edit.range.location + delta + length, length: 0))
            delta += length - edit.range.length
        }
        for edit in sorted.reversed() { output.replaceCharacters(in: edit.range, with: edit.replacement) }
        return AppliedEdits(text: output as String, inverse: inverse, carets: carets)
    }

    static func transformed(_ offset: Int, by edit: TextEdit) -> Int {
        if offset < edit.range.location { return offset }
        if offset <= NSMaxRange(edit.range) { return edit.range.location + (edit.replacement as NSString).length }
        return offset + (edit.replacement as NSString).length - edit.range.length
    }
}
