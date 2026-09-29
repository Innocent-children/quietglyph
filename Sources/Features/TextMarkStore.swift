import Foundation

final class TextMarkStore {
    struct Mark: Equatable { var range: NSRange; var color: String }
    private(set) var marks: [Mark] = []
    func set(_ ranges: [NSRange], color: String) {
        for range in ranges where range.length > 0 {
            marks.removeAll { $0.range == range }
            if color != "Clear" { marks.append(Mark(range: range, color: color)) }
        }
    }
    func clear(in ranges: [NSRange]) {
        marks.removeAll { mark in ranges.contains { NSIntersectionRange(mark.range, $0).length > 0 } }
    }
    func restore(_ values: [Mark]) { marks = values }
    func apply(_ edits: [TextEdit]) {
        for edit in edits.sorted(by: { $0.range.location > $1.range.location }) {
            marks = marks.compactMap { mark in
                let start = EditTransaction.transformed(mark.range.location, by: edit)
                let end = EditTransaction.transformed(NSMaxRange(mark.range), by: edit)
                return end > start ? Mark(range: NSRange(location: start, length: end - start), color: mark.color) : nil
            }
        }
    }
}
