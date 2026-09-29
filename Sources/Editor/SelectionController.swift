import Foundation

final class SelectionController {
    var ranges: [NSRange] = [NSRange(location: 0, length: 0)]
    var columnMode = false
    private(set) var rectangleColumns: ClosedRange<Int>?
    private var anchors: [Int] = []
    private var heads: [Int] = []
    private var preferredColumns: [Int] = []
    func restoreRectangle(_ columns: ClosedRange<Int>?) { rectangleColumns = columns }
    func set(_ values: [NSRange], text: NSString) {
        if values != ranges { rectangleColumns = nil }
        anchors = []; heads = []; preferredColumns = []
        var seen = Set<String>()
        let sorted = values.filter { TextRanges.valid($0, in: text) }.map { TextRanges.composed($0, in: text) }
            .sorted { $0.location < $1.location }.filter { seen.insert("\($0.location):\($0.length)").inserted }
        var accepted: [NSRange] = []
        for range in sorted {
            if let last = accepted.last, range.location < NSMaxRange(last) { continue }
            accepted.append(range)
        }
        ranges = accepted.isEmpty ? [NSRange(location: 0, length: 0)] : accepted
    }
    func rectangle(from first: Int, to last: Int, columns: ClosedRange<Int>, text: NSString, tabWidth: Int = 4) {
        let lines = TextRanges.lines(text)
        guard min(first, last) < lines.count, max(first, last) >= 0 else { return }
        rectangleColumns = max(0, columns.lowerBound)...max(0, columns.upperBound)
        anchors = []; heads = []; preferredColumns = []
        ranges = (max(0, min(first, last))...min(lines.count - 1, max(first, last))).map { index in
            let content = TextRanges.lineContent(lines[index], in: text)
            let range = ColumnGeometry.range(columns, in: text.substring(with: content), tabWidth: tabWidth)
            return NSRange(location: content.location + range.location, length: range.length)
        }
    }

    func replacements(_ values: [String], text: NSString, tabWidth: Int) -> [TextEdit] {
        zip(ranges, values).map { range, value in
            guard let columns = rectangleColumns else { return TextEdit(range: range, replacement: value) }
            let line = TextRanges.lineContent(text.lineRange(for: NSRange(location: range.location, length: 0)), in: text)
            var edit = ColumnGeometry.edit(columns, in: text.substring(with: line), replacement: value, tabWidth: tabWidth)
            edit.range.location += line.location
            return edit
        }
    }

    enum Movement { case left, right, up, down, lineStart, lineEnd, documentStart, documentEnd, wordLeft, wordRight }

    func move(_ direction: Movement, extending: Bool, text: NSString, tabWidth: Int) {
        rectangleColumns = nil
        if heads.count != ranges.count {
            anchors = ranges.map(\.location)
            heads = ranges.map(NSMaxRange)
            preferredColumns = []
        }
        let lines = TextRanges.lines(text)
        for i in ranges.indices {
            let old = heads[i]
            let index = lines.lastIndex(where: { $0.location <= old }) ?? 0
            let content = TextRanges.lineContent(lines[index], in: text)
            var next = old
            switch direction {
            case .left:
                next = !extending && ranges[i].length > 0 ? ranges[i].location : old > 0 ? text.rangeOfComposedCharacterSequence(at: old - 1).location : 0
            case .right:
                next = !extending && ranges[i].length > 0 ? NSMaxRange(ranges[i]) : old < text.length ? NSMaxRange(text.rangeOfComposedCharacterSequence(at: old)) : text.length
            case .lineStart: next = content.location
            case .lineEnd: next = NSMaxRange(content)
            case .documentStart: next = 0
            case .documentEnd: next = text.length
            case .wordLeft, .wordRight:
                let backwards = direction == .wordLeft
                let word = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
                var passedWord = false
                while backwards ? next > 0 : next < text.length {
                    let unit = text.rangeOfComposedCharacterSequence(at: backwards ? next - 1 : next)
                    let isWord = text.substring(with: unit).unicodeScalars.contains(where: word.contains)
                    if passedWord && !isWord { break }
                    passedWord = passedWord || isWord
                    next = backwards ? unit.location : NSMaxRange(unit)
                }
            case .up, .down:
                if preferredColumns.count != ranges.count {
                    preferredColumns = heads.map { head in
                        let line = TextRanges.lineContent(text.lineRange(for: NSRange(location: head, length: 0)), in: text)
                        return ColumnGeometry.column(at: head - line.location, in: text.substring(with: line), tabWidth: tabWidth)
                    }
                }
                let target = min(max(0, index + (direction == .up ? -1 : 1)), lines.count - 1)
                let line = TextRanges.lineContent(lines[target], in: text)
                next = line.location + ColumnGeometry.position(at: preferredColumns[i], in: text.substring(with: line), tabWidth: tabWidth).offset
            }
            heads[i] = next
            if !extending { anchors[i] = next }
            ranges[i] = NSRange(location: min(anchors[i], next), length: abs(anchors[i] - next))
        }
        if direction != .up && direction != .down { preferredColumns = [] }
        var accepted: [Int] = []
        for index in ranges.indices.sorted(by: { ranges[$0].location < ranges[$1].location }) {
            if let previous = accepted.last,
               ranges[index] == ranges[previous] || ranges[index].location < NSMaxRange(ranges[previous]) { continue }
            accepted.append(index)
        }
        ranges = accepted.map { ranges[$0] }
        anchors = accepted.map { anchors[$0] }
        heads = accepted.map { heads[$0] }
        if !preferredColumns.isEmpty { preferredColumns = accepted.map { preferredColumns[$0] } }
    }
}
