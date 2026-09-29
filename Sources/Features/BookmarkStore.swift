import Foundation

final class BookmarkStore {
    private(set) var offsets: [Int] = []
    func toggle(_ offset: Int) {
        if let i = offsets.firstIndex(of: offset) { offsets.remove(at: i) }
        else { offsets.append(offset); offsets.sort() }
    }
    func clear() { offsets.removeAll() }
    func add(_ values: [Int]) { offsets = Array(Set(offsets + values)).sorted() }
    func restore(_ values: [Int]) { offsets = values }
    func invert(in text: NSString) {
        offsets = TextRanges.lines(text).filter { line in !offsets.contains { text.lineRange(for: NSRange(location: min($0, text.length), length: 0)).location == line.location } }.map(\.location)
    }
    func next(after offset: Int, backwards: Bool = false) -> Int? {
        backwards ? offsets.last(where: { $0 < offset }) ?? offsets.last : offsets.first(where: { $0 > offset }) ?? offsets.first
    }
    func apply(_ edits: [TextEdit]) {
        for edit in edits.sorted(by: { $0.range.location > $1.range.location }) {
            offsets = Array(Set(offsets.map { EditTransaction.transformed($0, by: edit) })).sorted()
        }
    }
}
